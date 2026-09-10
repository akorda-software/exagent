defmodule ExAgent.ExecutionScope do
  @moduledoc """
  Ephemeral admission and accounting for one execution tree.

  The handle is runtime-only: do not serialize it. Each node retains its own
  restrictions and every admission checks all ancestors atomically. Model slots
  are fail-fast, never held while tools or delegates run. Usage is reconciled by
  operation identity; this is not exactly-once execution of external effects.

  Deadlines stop admission and are propagated as native model/tool timeouts by
  the core. Arbitrary application callbacks are not preempted or sandboxed.
  A lost scope stops independently running descendants; the root caller detects
  loss at cooperative boundaries rather than having its application process killed.
  """
  use GenServer

  alias ExAgent.{CostGuard, Model, Permissions, UsageLimits}
  alias ExAgent.Message.Usage

  @enforce_keys [:pid, :token, :run_id, :root_run_id]
  defstruct [:pid, :token, :run_id, :root_run_id, :parent_run_id, :deadline]

  @type t :: %__MODULE__{
          pid: pid(),
          token: reference(),
          run_id: String.t(),
          root_run_id: String.t(),
          parent_run_id: String.t() | nil,
          deadline: integer() | nil
        }

  @doc false
  def start(run_id, model, opts) do
    with :ok <- validate_options(opts),
         {:ok, pid} <- GenServer.start(__MODULE__, {self(), run_id, identity(model), opts}) do
      call(pid, :root)
    end
  end

  @doc false
  def join(%__MODULE__{} = parent, run_id, model, opts) do
    with :ok <- validate_options(opts) do
      call(parent.pid, {:join, parent.token, run_id, identity(model), opts})
    end
  end

  @doc false
  def check(scope), do: call(scope.pid, {:check, scope.token})

  @doc false
  def check_request(scope), do: call(scope.pid, {:request_check, scope.token})

  @doc false
  def watch_worker(scope) do
    with :ok <- check(scope), do: {:ok, watch(scope.pid, self(), nil)}
  end

  @doc false
  def admit_request(scope, id, model) do
    with {:ok, descriptors} <- call(scope.pid, {:pricing, scope.token}),
         {:ok, _} <- estimate(descriptors, model, zero_usage(), :admission),
         :ok <- call(scope.pid, {:admit_request, scope.token, id, model, descriptors}) do
      :ok
    end
  end

  @doc false
  def admit_tools(scope, id, count), do: call(scope.pid, {:admit_tools, scope.token, id, count})

  @doc "Replaces the cumulative usage snapshot of one model request."
  def record_usage(scope, id, usage, complete? \\ false) do
    with :ok <- validate_usage(usage),
         {:ok, model, descriptors, previous} <- call(scope.pid, {:operation, scope.token, id}) do
      complete? = complete? and complete_usage?(usage)
      usage = preserve_reported_usage(previous, usage)
      estimates = if usage, do: estimate(descriptors, model, usage, :record), else: {:ok, %{}}

      {costs, error} =
        case estimates do
          {:ok, costs} -> {costs, nil}
          {:error, reason, costs} -> {costs, reason}
        end

      with :ok <- call(scope.pid, {:record, scope.token, id, usage, costs, complete?}) do
        if error, do: {:error, error}, else: :ok
      end
    end
  end

  @doc false
  def finish_request(scope, id), do: call(scope.pid, {:finish_request, scope.token, id})

  @doc "Accounts legacy tool-contributed usage once, without inventing its model's price."
  def contribute(scope, id, %Usage{} = usage),
    do: call(scope.pid, {:contribute, scope.token, id, usage})

  def contribute(_scope, _id, nil), do: :ok

  @doc false
  def snapshot(scope), do: call(scope.pid, {:snapshot, scope.token})

  # Read the already-priced operation without invoking estimators again. This
  # projection contains no model/configuration and is not an accounting mutation.
  @doc false
  def request_snapshot(scope, id), do: call(scope.pid, {:request_snapshot, scope.token, id})

  @doc false
  def accounted?(scope, run_id), do: call(scope.pid, {:accounted, scope.token, run_id}) == true

  @doc false
  def finish_run(scope), do: call(scope.pid, {:finish_run, scope.token})

  @doc false
  def stop(scope) do
    try do
      GenServer.stop(scope.pid, :normal)
    catch
      :exit, _ -> :ok
    end
  end

  @doc false
  def authorize(scope, name, tool_call) do
    with {:ok, policies} <- call(scope.pid, {:policies, scope.token}) do
      decisions =
        Enum.map(policies, fn {permissions, approve} ->
          action = if permissions, do: Permissions.decide(permissions, name), else: :allow
          {action, approve}
        end)

      cond do
        Enum.any?(decisions, fn {action, _} -> action not in [:allow, :ask] end) ->
          :deny

        Enum.all?(decisions, fn {action, approve} ->
          Permissions.resolve(action, tool_call, approve) == :allow
        end) ->
          if check(scope) == :ok, do: :allow, else: :deny

        true ->
          :deny
      end
    else
      _ -> :deny
    end
  end

  @doc false
  def remaining_timeout(%__MODULE__{deadline: nil}, timeout), do: timeout

  def remaining_timeout(%__MODULE__{deadline: deadline}, timeout) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    if is_integer(timeout), do: min(timeout, remaining), else: remaining
  end

  defp call(pid, message) do
    try do
      GenServer.call(pid, message)
    catch
      :exit, _ -> {:error, :execution_scope_closed}
    end
  end

  @impl true
  def init({owner, run_id, model_id, opts}) do
    node = node(owner, run_id, model_id, opts, nil)

    {:ok,
     %{
       owner: owner,
       root: node.token,
       nodes: %{node.token => node},
       operations: %{},
       batches: MapSet.new()
     }}
  end

  @impl true
  def handle_call(:root, _, state), do: {:reply, {:ok, handle(state, state.root)}, state}

  def handle_call({:join, parent_token, run_id, model_id, opts}, {owner, _}, state) do
    with {:ok, parent} <- active_node(state, parent_token),
         false <- Enum.any?(state.nodes, fn {_, node} -> node.run_id == run_id end) do
      child = node(owner, run_id, model_id, opts, parent)
      child = %{child | guardian: watch(self(), owner, state.owner)}
      state = put_in(state.nodes[child.token], child)
      {:reply, {:ok, handle(state, child.token)}, state}
    else
      true -> {:reply, {:error, :duplicate_run_id}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:check, token}, _, state) do
    reply = with {:ok, _} <- active_node(state, token), do: :ok
    {:reply, reply, state}
  end

  def handle_call({:request_check, token}, _, state),
    do: {:reply, admission_check(state, token), state}

  def handle_call({:pricing, token}, _, state) do
    reply =
      with {:ok, node} <- active_node(state, token) do
        {:ok,
         Enum.map(node.ancestors, fn token ->
           ancestor = state.nodes[token]

           %{
             token: token,
             estimator: ancestor.estimator,
             model_id: ancestor.estimator_model_id,
             required: ancestor.limits.max_budget_cents != nil
           }
         end)}
      end

    {:reply, reply, state}
  end

  def handle_call({:admit_request, token, id, model, descriptors}, _, state) do
    with :ok <- admission_check(state, token),
         false <- Map.has_key?(state.operations, id),
         :ok <- concurrency_check(state, token) do
      node = state.nodes[token]

      operation = %{
        kind: :model,
        token: token,
        ancestors: node.ancestors,
        model: model,
        descriptors: descriptors,
        usage: nil,
        costs: %{},
        complete: false,
        active: true
      }

      state = put_in(state.operations[id], operation)

      state =
        Enum.reduce(node.ancestors, state, fn ancestor, state ->
          update_in(state.nodes[ancestor].requests, &(&1 + 1))
        end)

      {:reply, :ok, state}
    else
      true -> {:reply, {:error, :duplicate_operation_id}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:admit_tools, token, id, count}, _, state) do
    with {:ok, node} <- active_node(state, token),
         true <- is_integer(count) and count >= 0,
         false <- MapSet.member?(state.batches, id),
         :ok <- resource_check(state, node),
         :ok <-
           check_ancestors(state, node, fn ancestor ->
             UsageLimits.check_tool_calls(ancestor.limits, ancestor.tools, count)
           end) do
      state =
        Enum.reduce(node.ancestors, state, fn ancestor, state ->
          update_in(state.nodes[ancestor].tools, &(&1 + count))
        end)

      {:reply, :ok, %{state | batches: MapSet.put(state.batches, id)}}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :invalid_tool_batch_admission}, state}
    end
  end

  def handle_call({:operation, token, id}, _, state) do
    reply =
      case Map.get(state.operations, id) do
        %{token: ^token} = operation ->
          {:ok, operation.model, operation.descriptors, operation.usage}

        _ ->
          {:error, :unknown_operation}
      end

    {:reply, reply, state}
  end

  def handle_call({:record, token, id, usage, costs, complete?}, _, state) do
    case Map.get(state.operations, id) do
      %{token: ^token, complete: true} = operation ->
        if usage == nil or usage == operation.usage,
          do: {:reply, :ok, state},
          else: {:reply, {:error, :request_already_finalized}, state}

      %{token: ^token} = operation ->
        operation = %{
          operation
          | usage: usage || operation.usage,
            costs: if(usage, do: costs, else: operation.costs),
            complete: complete? and complete_usage?(usage)
        }

        {:reply, :ok, put_in(state.operations[id], operation)}

      _ ->
        {:reply, {:error, :unknown_operation}, state}
    end
  end

  def handle_call({:finish_request, token, id}, _, state) do
    case Map.get(state.operations, id) do
      %{token: ^token} = operation ->
        {:reply, :ok, put_in(state.operations[id], %{operation | active: false})}

      _ ->
        {:reply, {:error, :unknown_operation}, state}
    end
  end

  def handle_call({:contribute, token, id, usage}, _, state) do
    with %{active: true} = node <- Map.get(state.nodes, token),
         :ok <- validate_usage(usage) do
      key = {:tool_usage, token, id}

      operation = %{
        kind: :external,
        token: token,
        ancestors: node.ancestors,
        usage: usage,
        costs: %{},
        complete: complete_usage?(usage),
        active: false
      }

      {:reply, :ok, put_in(state.operations[key], operation)}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :execution_scope_closed}, state}
    end
  end

  def handle_call({:snapshot, token}, _, state) do
    if Map.has_key?(state.nodes, token),
      do: {:reply, {:ok, totals(state, token)}, state},
      else: {:reply, {:error, :invalid_execution_scope}, state}
  end

  def handle_call({:request_snapshot, token, id}, _, state) do
    reply =
      case Map.get(state.operations, id) do
        %{token: ^token} = operation ->
          cost = Map.get(operation.costs, token)

          {:ok,
           %{
             usage: operation.usage,
             usage_status: if(operation.complete, do: :complete, else: :partial),
             cost_cents: cost,
             cost_status: if(is_number(cost), do: :known, else: :unknown)
           }}

        _ ->
          {:error, :unknown_operation}
      end

    {:reply, reply, state}
  end

  def handle_call({:accounted, token, run_id}, _, state) do
    found =
      Enum.any?(state.nodes, fn {_, node} -> node.run_id == run_id and token in node.ancestors end)

    {:reply, found, state}
  end

  def handle_call({:policies, token}, _, state) do
    reply =
      with {:ok, node} <- active_node(state, token) do
        {:ok,
         Enum.map(node.ancestors, fn token ->
           {state.nodes[token].permissions, state.nodes[token].approve}
         end)}
      end

    {:reply, reply, state}
  end

  def handle_call({:finish_run, token}, _, state) do
    cancel_descendants(state, token, token)
    {:reply, :ok, close_node(state, token)}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, owner, _}, state) do
    if owner == state.owner do
      cancel_descendants(state, state.root)
      {:stop, :normal, state}
    else
      tokens = for {token, node} <- state.nodes, node.monitor == monitor, do: token

      state =
        Enum.reduce(tokens, state, fn token, state ->
          cancel_descendants(state, token)
          close_node(state, token)
        end)

      {:noreply, state}
    end
  end

  @impl true
  def terminate(_, state), do: cancel_descendants(state, state.root)

  defp node(owner, run_id, model_id, opts, parent) do
    token = make_ref()
    inherited = if parent, do: parent.estimator, else: nil
    estimator = Keyword.get(opts, :estimate_cost, inherited)

    estimator_model_id =
      if parent && not Keyword.has_key?(opts, :estimate_cost),
        do: parent.estimator_model_id,
        else: model_id

    deadline = minimum(Keyword.get(opts, :deadline), if(parent, do: parent.deadline))

    %{
      token: token,
      run_id: run_id,
      parent_run_id: if(parent, do: parent.run_id),
      root_run_id: if(parent, do: parent.root_run_id, else: run_id),
      owner: owner,
      monitor: Process.monitor(owner),
      guardian: nil,
      active: true,
      ancestors: if(parent, do: parent.ancestors, else: []) ++ [token],
      limits: Keyword.get(opts, :usage_limits) || %UsageLimits{},
      estimator: estimator,
      estimator_model_id: estimator_model_id,
      permissions: Keyword.get(opts, :permissions),
      approve: Keyword.get(opts, :approve),
      deadline: deadline,
      max_concurrent: Keyword.get(opts, :max_concurrent_requests),
      requests: 0,
      tools: 0
    }
  end

  defp handle(state, token) do
    node = state.nodes[token]

    %__MODULE__{
      pid: self(),
      token: token,
      run_id: node.run_id,
      root_run_id: node.root_run_id,
      parent_run_id: node.parent_run_id,
      deadline: node.deadline
    }
  end

  defp active_node(state, token) do
    case Map.get(state.nodes, token) do
      %{active: true} = node ->
        cond do
          Enum.any?(node.ancestors, &(not state.nodes[&1].active)) ->
            {:error, :execution_scope_closed}

          node.deadline != nil and System.monotonic_time(:millisecond) >= node.deadline ->
            {:error, :deadline_exceeded}

          true ->
            {:ok, node}
        end

      _ ->
        {:error, :execution_scope_closed}
    end
  end

  defp admission_check(state, token) do
    with {:ok, node} <- active_node(state, token) do
      check_ancestors(state, node, fn ancestor ->
        total = totals(state, ancestor.token)

        if ancestor.limits.max_budget_cents != nil and total.cost_cents == nil do
          {:error, :cost_unknown}
        else
          UsageLimits.check_before_request(
            ancestor.limits,
            total.usage,
            ancestor.requests,
            total.cost_cents
          )
        end
      end)
    end
  end

  defp resource_check(state, node) do
    check_ancestors(state, node, fn ancestor ->
      total = totals(state, ancestor.token)

      UsageLimits.check_before_request(
        %{ancestor.limits | request_limit: nil},
        total.usage,
        0,
        total.cost_cents
      )
    end)
  end

  defp check_ancestors(state, node, fun) do
    Enum.reduce_while(node.ancestors, :ok, fn token, :ok ->
      case fun.(state.nodes[token]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp concurrency_check(state, token) do
    node = state.nodes[token]

    check_ancestors(state, node, fn ancestor ->
      active =
        Enum.count(state.operations, fn {_, operation} ->
          operation.active and ancestor.token in operation.ancestors
        end)

      if ancestor.max_concurrent && active >= ancestor.max_concurrent,
        do: {:error, {:concurrency_limit_exceeded, ancestor.max_concurrent}},
        else: :ok
    end)
  end

  defp totals(state, token) do
    operations =
      for {_, operation} <- state.operations, token in operation.ancestors, do: operation

    usage = Enum.reduce(operations, zero_usage(), &merge_usage(&2, &1.usage))
    known? = Enum.all?(operations, & &1.complete)
    costs = Enum.map(operations, &Map.get(&1.costs, token))
    cost = if Enum.all?(costs, &is_number/1), do: Enum.sum(costs), else: nil
    node = state.nodes[token]

    %{
      usage: usage,
      usage_status: if(known?, do: :complete, else: :partial),
      cost_cents: cost,
      cost_status: if(is_number(cost), do: :known, else: :unknown),
      request_count: node.requests,
      tool_calls: node.tools,
      root_run_id: node.root_run_id,
      parent_run_id: node.parent_run_id
    }
  end

  defp estimate(descriptors, model, usage, phase) do
    {costs, error} =
      Enum.reduce(descriptors, {%{}, nil}, fn descriptor, {costs, error} ->
        estimate =
          cond do
            not complete_usage?(usage) ->
              :unknown

            descriptor.estimator == nil ->
              :unknown

            is_function(descriptor.estimator, 1) and descriptor.model_id != identity(model) ->
              :unknown

            true ->
              CostGuard.estimate(descriptor.estimator, model, usage)
          end

        {cost, current_error} =
          case estimate do
            {:ok, cost} -> {cost, nil}
            :unknown -> {nil, if(descriptor.required, do: :cost_estimator_required)}
            {:error, reason} -> {nil, reason}
          end

        {Map.put(costs, descriptor.token, cost), error || current_error}
      end)

    cond do
      error == nil -> {:ok, costs}
      phase == :admission -> {:error, error}
      true -> {:error, error, costs}
    end
  end

  defp close_node(state, token) do
    case Map.get(state.nodes, token) do
      nil ->
        state

      node ->
        Process.demonitor(node.monitor, [:flush])
        if node.guardian, do: send(node.guardian, :finished)
        state = put_in(state.nodes[token].active, false)

        operations =
          Map.new(state.operations, fn {id, operation} ->
            {id, if(operation.token == token, do: %{operation | active: false}, else: operation)}
          end)

        %{state | operations: operations}
    end
  end

  defp cancel_descendants(state, token, except \\ nil) do
    Enum.each(state.nodes, fn {_, node} ->
      if node.active and node.token != except and token in node.ancestors and
           node.owner != state.owner,
         do: Process.exit(node.owner, :kill)
    end)
  end

  defp watch(_scope, owner, root_owner) when owner == root_owner, do: nil

  defp watch(scope, owner, _) do
    spawn(fn ->
      scope_monitor = Process.monitor(scope)
      owner_monitor = Process.monitor(owner)

      receive do
        :finished -> :ok
        {:DOWN, ^scope_monitor, :process, ^scope, _} -> Process.exit(owner, :kill)
        {:DOWN, ^owner_monitor, :process, ^owner, _} -> :ok
      end
    end)
  end

  defp validate_options(opts) do
    with :ok <- UsageLimits.validate(Keyword.get(opts, :usage_limits)),
         true <- is_nil(opts[:deadline]) or is_integer(opts[:deadline]),
         true <-
           is_nil(opts[:max_concurrent_requests]) or
             (is_integer(opts[:max_concurrent_requests]) and opts[:max_concurrent_requests] > 0),
         true <-
           is_nil(opts[:estimate_cost]) or is_function(opts[:estimate_cost], 1) or
             is_function(opts[:estimate_cost], 2) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_execution_scope_options}
    end
  end

  defp identity(model), do: {Model.system(model), Model.model_name(model)}

  defp validate_usage(nil), do: :ok

  defp validate_usage(%Usage{} = usage) do
    if Enum.all?(
         [usage.input_tokens, usage.output_tokens],
         &(is_nil(&1) or (is_integer(&1) and &1 >= 0))
       ) and is_map(usage.details), do: :ok, else: {:error, :invalid_model_usage}
  end

  defp validate_usage(_), do: {:error, :invalid_model_usage}

  defp complete_usage?(%Usage{input_tokens: input, output_tokens: output}),
    do: is_integer(input) and is_integer(output)

  defp complete_usage?(_), do: false

  defp preserve_reported_usage(_, nil), do: nil
  defp preserve_reported_usage(nil, usage), do: usage

  defp preserve_reported_usage(previous, usage),
    do: %Usage{
      input_tokens: usage.input_tokens || previous.input_tokens,
      output_tokens: usage.output_tokens || previous.output_tokens,
      details: snapshot_details(previous.details, usage.details)
    }

  defp snapshot_details(a, b),
    do:
      Map.merge(a, b, fn _, x, y ->
        if is_map(x) and is_map(y), do: snapshot_details(x, y), else: y
      end)

  defp minimum(nil, value), do: value
  defp minimum(value, nil), do: value
  defp minimum(a, b), do: min(a, b)
  defp zero_usage, do: %Usage{input_tokens: 0, output_tokens: 0}
  defp merge_usage(acc, nil), do: acc

  defp merge_usage(acc, usage),
    do: %Usage{
      input_tokens: acc.input_tokens + (usage.input_tokens || 0),
      output_tokens: acc.output_tokens + (usage.output_tokens || 0),
      details: merge_details(acc.details, usage.details)
    }

  defp merge_details(a, b),
    do:
      Map.merge(a, b, fn _, x, y ->
        cond do
          is_number(x) and is_number(y) -> x + y
          is_map(x) and is_map(y) -> merge_details(x, y)
          true -> y
        end
      end)
end

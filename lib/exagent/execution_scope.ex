defmodule ExAgent.ExecutionScope do
  @moduledoc """
  Ephemeral admission and accounting for one execution tree.

  The handle is runtime-only: do not serialize it. Each node retains its own
  restrictions and every admission checks all ancestors atomically. Model slots
  are fail-fast, never held while tools or delegates run. Usage is reconciled by
  operation identity; this is not exactly-once execution of external effects.
  `request_count` counts admitted Model attempts (not necessarily HTTP requests
  for a custom Model); `tool_calls` counts exact batch reservations, not dispatches
  or successful effects. Terminal finalization is independent of metric coverage.

  Deadlines stop admission and are propagated as native model/tool timeouts by
  the core. Arbitrary application callbacks are not preempted or sandboxed.
  A lost scope stops independently running descendants; the root caller detects
  loss at cooperative boundaries rather than having its application process killed.
  """
  use GenServer

  alias ExAgent.{CostGuard, Model, Permissions, UsageLimits, Retention}
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

  # A host composition owns restrictions and totals, never a model operation.
  # The marker is trusted runtime state, not an option or authority from JSON.
  @doc false
  def start_structural(run_id, opts) do
    with :ok <- validate_structural_options(opts),
         {:ok, pid} <- GenServer.start(__MODULE__, {:structural, self(), run_id, opts}) do
      call(pid, :root)
    end
  end

  @doc false
  def validate_structural_options(opts) do
    with :ok <- validate_options(opts),
         false <- is_function(opts[:estimate_cost], 1) do
      :ok
    else
      true -> {:error, :structural_scope_requires_model_aware_estimator}
      error -> error
    end
  end

  @doc false
  def join(%__MODULE__{} = parent, run_id, model, opts) do
    with :ok <- validate_options(opts) do
      call(parent.pid, {:join, parent.token, run_id, identity(model), opts})
    end
  end

  @doc false
  def join_for(%__MODULE__{} = parent, run_id, model, opts, owner) when is_pid(owner) do
    with :ok <- validate_options(opts) do
      call(parent.pid, {:join_for, parent.token, run_id, identity(model), opts, owner})
    end
  end

  @doc false
  def check(scope), do: call(scope.pid, {:check, scope.token})

  # Not ledger rollback: any operation or descendant forbids removal.
  @doc false
  def discard_empty_child(%__MODULE__{} = parent, %__MODULE__{pid: pid} = child)
      when parent.pid == pid,
      do: call(pid, {:discard_empty_child, parent.token, child.token})

  @doc false
  def check_request(scope), do: call(scope.pid, {:request_check, scope.token})

  @doc false
  def watch_worker(scope) do
    with :ok <- check(scope), do: {:ok, watch(scope.pid, self(), nil)}
  end

  @doc false
  def admit_request(scope, id, model) do
    with {:ok, descriptors} <- call(scope.pid, {:pricing, scope.token}),
         :ok <- accounting_preflight(descriptors, model),
         :ok <- call(scope.pid, {:admit_request, scope.token, id, model, descriptors}) do
      :ok
    end
  end

  @doc false
  def admit_tools(scope, id, count), do: call(scope.pid, {:admit_tools, scope.token, id, count})

  @doc false
  def admit_retry_tool(scope, id, request),
    do: call(scope.pid, {:admit_retry_tool, scope.token, id, request})

  @doc false
  def check_reserved_tools(scope, id),
    do: call(scope.pid, {:check_reserved_tools, scope.token, id})

  @doc "Replaces the cumulative usage snapshot of one model request."
  def record_usage(scope, id, usage, complete? \\ false) do
    {usage, retention_error} = Retention.usage(usage)

    with :ok <- validate_usage(usage),
         {:ok, model, descriptors, previous, previous_costs} <-
           call(scope.pid, {:operation, scope.token, id, usage, complete?}) do
      terminal_usage = usage
      usage = preserve_reported_usage(previous, usage) |> Usage.qualify()
      usage = if terminal_usage == nil, do: Usage.partial(usage), else: usage
      {usage, merged_retention_error} = Retention.usage(usage)

      estimates =
        if terminal_usage == nil,
          do: {:ok, previous_costs},
          else: estimate(descriptors, model, usage)

      {costs, error} =
        case estimates do
          {:ok, costs} -> {costs, nil}
          {:error, reason, costs} -> {costs, reason}
        end

      costs = preserve_cost_subtotals(descriptors, usage, costs, previous_costs)

      result =
        if retention_error || merged_retention_error || error,
          do: {:error, retention_error || merged_retention_error || error},
          else: accounting_check(descriptors, usage, costs, terminal_usage != nil)

      # Bound the result before sending it to the ledger, whose terminal reply
      # is retained and returned verbatim on duplicate accounting notifications.
      result =
        case result do
          {:error, reason} -> {:error, Retention.reason(reason)}
          :ok -> :ok
        end

      usage =
        case result do
          {:error, {:retention_limit_exceeded, %{boundary: boundary, bytes: bytes, limit: limit}}} ->
            %{
              usage
              | payload_omitted: usage.payload_omitted || Retention.marker(boundary, bytes, limit)
            }

          _ ->
            usage
        end

      call(scope.pid, {:record, scope.token, id, usage, costs, complete?, terminal_usage, result})
    else
      {:recorded, result} -> result
      error -> error
    end
  end

  @doc false
  def finish_request(scope, id), do: call(scope.pid, {:finish_request, scope.token, id})

  @doc "Accounts legacy tool-contributed usage once, without inventing its model's price."
  def contribute(scope, id, %Usage{} = usage) do
    {usage, error} = Retention.usage(usage)
    result = call(scope.pid, {:contribute, scope.token, id, usage})
    if error, do: {:error, error}, else: result
  end

  def contribute(_scope, _id, nil), do: :ok

  @doc false
  def observe_tool(scope, id, input), do: call(scope.pid, {:observe_tool, scope.token, id, input})

  @doc false
  def retain_uncertain_tool_usage(scope, id),
    do: call(scope.pid, {:retain_uncertain_tool_usage, scope.token, id})

  @doc false
  def snapshot(scope), do: call(scope.pid, {:snapshot, scope.token})

  @doc false
  def export(scope), do: call(scope.pid, {:export, scope.token})

  @doc false
  def restore(scope, data), do: call(scope.pid, {:restore, scope.token, data})

  @doc false
  def export_tree(scope), do: call(scope.pid, {:export_tree, scope.token})

  @doc false
  def export_node(scope), do: call(scope.pid, {:export_node, scope.token})

  @doc false
  def authority(scope), do: call(scope.pid, {:authority, scope.token})

  @doc false
  def restore_tree(scope, data), do: call(scope.pid, {:restore_tree, scope.token, data})

  @doc false
  def restore_composition_tree(scope, frame),
    do: call(scope.pid, {:restore_composition_tree, scope.token, frame})

  @doc false
  def decision(scope, name) do
    with {:ok, policies} <- call(scope.pid, {:policies, scope.token}) do
      actions =
        Enum.map(policies, fn {p, _} -> if p, do: Permissions.decide(p, name), else: :allow end)

      cond do
        :deny in actions -> :deny
        :ask in actions -> :ask
        true -> :allow
      end
    else
      _ -> :deny
    end
  end

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
  def init({:structural, owner, run_id, opts}) do
    {:ok, state} = init({owner, run_id, nil, opts})
    {:ok, put_in(state.nodes[state.root].structural, true)}
  end

  def init({owner, run_id, model_id, opts}) do
    node = node(owner, run_id, model_id, opts, nil)

    {:ok,
     %{
       owner: owner,
       root: node.token,
       nodes: %{node.token => node},
       operations: %{},
       tool_receipts: %{},
       batches: MapSet.new(),
       batch_counts: %{},
       retry_batches: %{}
     }}
  end

  @impl true
  def handle_call(:root, _, state), do: {:reply, {:ok, handle(state, state.root)}, state}

  def handle_call({:join_for, parent, run_id, model, opts, owner}, _, state),
    do: handle_call({:join, parent, run_id, model, opts}, {owner, nil}, state)

  def handle_call({:discard_empty_child, parent, token}, _, state) do
    with %{parent_run_id: parent_id, requests: 0, tools: 0} <- state.nodes[token],
         %{run_id: ^parent_id} <- state.nodes[parent],
         false <-
           Enum.any?(state.nodes, fn {id, node} -> id != token and token in node.ancestors end),
         false <- Enum.any?(state.operations, fn {_, op} -> token in op.ancestors end),
         false <- Enum.any?(state.retry_batches, fn {_, batch} -> batch.token == token end) do
      state = close_node(state, token)
      {:reply, :ok, %{state | nodes: Map.delete(state.nodes, token)}}
    else
      _ -> {:reply, {:error, :scope_child_not_empty}, state}
    end
  end

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
    reply =
      with {:ok, node} <- active_node(state, token),
           do:
             check_ancestors(state, node, fn ancestor ->
               Retention.usage_error(totals(state, ancestor.token).usage)
             end)

    {:reply, reply, state}
  end

  def handle_call({:request_check, token}, _, state),
    do: {:reply, admission_check(state, token), state}

  def handle_call({:pricing, token}, _, state) do
    reply =
      with {:ok, node} <- effect_node(state, token) do
        {:ok,
         Enum.map(node.ancestors, fn token ->
           ancestor = state.nodes[token]

           %{
             token: token,
             estimator: ancestor.estimator,
             model_id: ancestor.estimator_model_id,
             limits: ancestor.limits,
             bounded:
               Enum.any?(ancestor.ancestors, &(state.nodes[&1].limits.request_limit != nil))
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
        finalized: false,
        terminal_usage: nil,
        record_result: :ok,
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
    with {:ok, node} <- effect_node(state, token),
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

      {:reply, :ok,
       %{
         state
         | batches: MapSet.put(state.batches, id),
           batch_counts: Map.put(state.batch_counts, id, count)
       }}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :invalid_tool_batch_admission}, state}
    end
  end

  def handle_call({:check_reserved_tools, token, id}, _, state) do
    result =
      with {:ok, node} <- active_node(state, token),
           true <- MapSet.member?(state.batches, id),
           %{token: ^token} <- Map.get(state.operations, id),
           :ok <- resource_check(state, node) do
        check_ancestors(state, node, fn ancestor ->
          with :ok <- UsageLimits.check_tool_calls(ancestor.limits, ancestor.tools, 0) do
            if ancestor.limits.request_limit && ancestor.requests > ancestor.limits.request_limit,
              do: {:error, {:usage_limit_exceeded, :requests, ancestor.requests}},
              else: :ok
          end
        end)
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_tool_batch_admission}
      end

    {:reply, result, state}
  end

  def handle_call({:admit_retry_tool, token, id, request}, _, state) do
    with {:ok, node} <- effect_node(state, token),
         true <- ExAgent.Continuation.Record.text?(id) and MapSet.member?(state.batches, request),
         %{token: ^token} <- state.operations[request],
         :ok <- resource_check(state, node) do
      case state.retry_batches[id] do
        %{token: ^token, request_id: ^request} ->
          {:reply, :ok, state}

        nil ->
          case check_ancestors(state, node, &UsageLimits.check_tool_calls(&1.limits, &1.tools, 1)) do
            :ok ->
              state =
                Enum.reduce(node.ancestors, state, fn ancestor, acc ->
                  update_in(acc.nodes[ancestor].tools, &(&1 + 1))
                end)

              {:reply, :ok, put_in(state.retry_batches[id], %{token: token, request_id: request})}

            error ->
              {:reply, error, state}
          end

        _ ->
          {:reply, {:error, :invalid_retry_admission}, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :invalid_retry_admission}, state}
    end
  end

  def handle_call({:operation, token, id, usage, complete?}, _, state) do
    reply =
      case Map.get(state.operations, id) do
        %{token: ^token, finalized: true} = operation ->
          if complete? and usage == operation.terminal_usage,
            do: {:recorded, operation.record_result},
            else: {:error, :request_already_finalized}

        %{token: ^token} = operation ->
          {:ok, operation.model, operation.descriptors, operation.usage, operation.costs}

        _ ->
          {:error, :unknown_operation}
      end

    {:reply, reply, state}
  end

  def handle_call({:record, token, id, usage, costs, complete?, terminal_usage, result}, _, state) do
    case Map.get(state.operations, id) do
      %{token: ^token, finalized: true} = operation ->
        if complete? and terminal_usage == operation.terminal_usage,
          do: {:reply, operation.record_result, state},
          else: {:reply, {:error, :request_already_finalized}, state}

      %{token: ^token} = operation ->
        operation = %{
          operation
          | usage: usage || operation.usage,
            costs: if(usage, do: costs, else: operation.costs),
            complete: complete? and Usage.complete?(usage),
            finalized: complete?,
            terminal_usage: terminal_usage,
            record_result: result
        }

        {:reply, result, put_in(state.operations[id], operation)}

      _ ->
        {:reply, {:error, :unknown_operation}, state}
    end
  end

  def handle_call({:finish_request, token, id}, _, state) do
    case Map.get(state.operations, id) do
      %{token: ^token} = operation ->
        usage = if operation.finalized, do: operation.usage, else: Usage.partial(operation.usage)

        {:reply, :ok,
         put_in(state.operations[id], %{operation | active: false, finalized: true, usage: usage})}

      _ ->
        {:reply, {:error, :unknown_operation}, state}
    end
  end

  def handle_call({:retain_uncertain_tool_usage, token, id}, from, state) do
    if Map.has_key?(state.operations, {:tool_usage, token, id}),
      do: {:reply, :ok, state},
      else: handle_call({:contribute, token, id, Usage.qualify(nil)}, from, state)
  end

  def handle_call({:contribute, token, id, usage}, _, state) do
    with %{active: true} = node <- Map.get(state.nodes, token),
         :ok <- executable_node(node),
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

  def handle_call({:observe_tool, token, id, input}, _, state) do
    alias ExAgent.Continuation.ToolEvidence
    key = {:tool_usage, token, id}
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(input))

    case state.tool_receipts[key] do
      {^fingerprint, observation, result} ->
        {:reply, {:ok, observation, result}, state}

      {_, _, _} ->
        {:reply, {:error, :tool_accounting_conflict}, state}

      nil ->
        with %{active: true} = node <- state.nodes[token],
             :ok <- executable_node(node),
             false <- Map.has_key?(state.operations, key) do
          {observation, usage, error} = ToolEvidence.observe(input)

          operation =
            if usage,
              do: %{
                kind: :external,
                token: token,
                ancestors: node.ancestors,
                usage: usage,
                costs: %{},
                complete: complete_usage?(usage),
                active: false
              }

          observation =
            if operation do
              ancestors =
                Map.new(node.ancestors, fn ancestor ->
                  {state.nodes[ancestor].run_id, Usage.to_map(priced_usage(operation, ancestor))}
                end)

              Map.put(observation, "application", %{
                "status" => "contributed",
                "complete" => operation.complete,
                "ancestors" => ancestors
              })
            else
              observation
            end

          candidate = if operation, do: put_in(state.operations[key], operation), else: state

          with true <- ToolEvidence.observation?(observation),
               {:ok, _} <- ExAgent.Continuation.ScopeLedger.export(candidate, &priced_usage/2) do
            result = if error, do: {:error, error}, else: :ok
            next = put_in(candidate.tool_receipts[key], {fingerprint, observation, result})
            {:reply, {:ok, observation, result}, next}
          else
            _ -> {:reply, {:error, :invalid_tool_accounting}, state}
          end
        else
          true -> {:reply, {:error, :tool_accounting_conflict}, state}
          _ -> {:reply, {:error, :execution_scope_closed}, state}
        end
    end
  end

  def handle_call({:snapshot, token}, _, state) do
    if Map.has_key?(state.nodes, token) do
      total = totals(state, token)

      rejected =
        Enum.any?(state.tool_receipts, fn {{:tool_usage, own, _}, {_, _, result}} ->
          token in state.nodes[own].ancestors and match?({:error, _}, result)
        end)

      total =
        if rejected,
          do: %{
            total
            | usage: Usage.partial(total.usage),
              usage_status: :partial,
              cost_cents: nil,
              cost_status: :unknown
          },
          else: total

      {:reply, {:ok, total}, state}
    else
      {:reply, {:error, :invalid_execution_scope}, state}
    end
  end

  def handle_call({:export, token}, _, state) do
    # The first runtime vertical supports one root. Tree restore is added at the
    # delegation seam, rather than flattening child budgets into a root subtotal.
    reply =
      if token == state.root and not state.nodes[token].structural and
           map_size(state.nodes) == 1 and map_size(state.retry_batches) == 0 do
        node = state.nodes[token]

        operations =
          Enum.map(state.operations, fn {id, operation} ->
            %{
              "id" => operation_key(id),
              "usage" => Usage.to_map(priced_usage(operation, token)),
              "complete" => operation.complete
            }
          end)

        {:ok,
         %{
           "scope_version" => 1,
           "run_id" => node.run_id,
           "requests" => node.requests,
           "tools" => node.tools,
           "operations" => operations,
           "batches" => state.batch_counts
         }}
      else
        {:error, :unsupported_continuation_tree}
      end

    {:reply, reply, state}
  end

  def handle_call({:export_tree, token}, _, state) do
    reply =
      if token == state.root,
        do: ExAgent.Continuation.ScopeLedger.export(state, &priced_usage/2),
        else: {:error, :invalid_execution_scope}

    {:reply, reply, state}
  end

  def handle_call({:export_node, token}, _, state) do
    case Map.fetch(state.nodes, token) do
      {:ok, node} ->
        operations =
          for {id, %{token: ^token} = operation} <- state.operations do
            %{
              "id" => operation_key(id),
              "usage" => Usage.to_map(priced_usage(operation, token)),
              "complete" => operation.complete
            }
          end

        batches =
          Map.filter(state.batch_counts, fn {id, _} ->
            match?(%{token: ^token}, state.operations[id])
          end)

        {:reply,
         {:ok,
          %{
            "scope_version" => 1,
            "run_id" => node.run_id,
            "requests" => Enum.count(operations, &match?(["model", _], &1["id"])),
            "tools" =>
              Enum.sum(Map.values(batches)) +
                Enum.count(state.retry_batches, fn {_, batch} -> batch.token == token end),
            "operations" => operations,
            "batches" => batches
          }}, state}

      :error ->
        {:reply, {:error, :invalid_execution_scope}, state}
    end
  end

  def handle_call({:restore_composition_tree, token, frame}, {owner, _}, state) do
    case composition_candidate(state, owner, token, frame) do
      {:ok, candidate} -> {:reply, :ok, candidate}
      _ -> {:reply, {:error, :invalid_scope_checkpoint}, state}
    end
  end

  def handle_call({:restore_tree, token, data}, _, state) do
    if token == state.root and map_size(state.operations) == 0 and
         map_size(state.batch_counts) == 0 do
      case ExAgent.Continuation.ScopeLedger.restore(state, data) do
        {:ok, restored} -> {:reply, :ok, restored}
        error -> {:reply, error, state}
      end
    else
      {:reply, {:error, :invalid_scope_checkpoint}, state}
    end
  end

  def handle_call({:restore, token, data}, _, state) do
    with true <- token == state.root and map_size(state.operations) == 0,
         true <- not state.nodes[token].structural,
         {:ok, operations, batches} <- restore_ledger(data, state.nodes[token].run_id, token) do
      node = %{state.nodes[token] | requests: data["requests"], tools: data["tools"]}

      {:reply, :ok,
       %{
         state
         | nodes: %{token => node},
           operations: operations,
           batches: MapSet.new(Map.keys(batches)),
           batch_counts: batches
       }}
    else
      _ -> {:reply, {:error, :invalid_scope_checkpoint}, state}
    end
  end

  def handle_call({:request_snapshot, token, id}, _, state) do
    reply =
      case Map.get(state.operations, id) do
        %{token: ^token} = operation ->
          cost = operation |> priced_usage(token) |> Usage.estimated_cost()

          {:ok,
           %{
             usage: priced_usage(operation, token),
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
         Enum.flat_map(node.ancestors, fn token ->
           n = state.nodes[token]

           [{n.permissions, n.approve}, {n.permission_floor, nil}] ++
             Enum.map(n.permission_floors, &{&1, nil})
         end)}
      end

    {:reply, reply, state}
  end

  def handle_call({:authority, token}, _, state) do
    reply =
      with {:ok, node} <- active_node(state, token),
           do: {:ok, ExAgent.Continuation.Authority.capture(node)}

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

  # Build a candidate without monitors, guardians, model callbacks or handles for
  # historical leaves. ScopeLedger still requires the exact tree and owns import.
  defp structural_candidate(state, owner, token, %{"frame_version" => version} = frame)
       when version in [10, 11] do
    active = for {id, n} <- frame["children"], n["status"] in ~w(running suspended), do: id

    with true <- owner == state.owner and token == state.root,
         {:ok, %{structural: true} = root} <- active_node(state, token),
         true <-
           state.operations == %{} and state.tool_receipts == %{} and
             state.batch_counts == %{} and state.retry_batches == %{} and
             MapSet.size(state.batches) == 0,
         :ok <- ExAgent.Continuation.Frame.validate(frame),
         true <- frame["run_id"] == root.run_id,
         true <-
           Enum.sort(Enum.map(state.nodes, fn {_, n} -> n.run_id end)) ==
             Enum.sort([root.run_id | active]),
         true <-
           Enum.all?(state.nodes, fn {t, n} ->
             n.active and n.requests == 0 and n.tools == 0 and
               (t == token or
                  (not n.structural and
                     n.parent_run_id == frame["children"][n.run_id]["parent_run_id"]))
           end) do
      ids = Enum.sort_by(Map.keys(frame["children"]), &composition_depth(frame, &1))

      nodes =
        Enum.reduce(ids, state.nodes, fn id, nodes ->
          child = frame["children"][id]

          if id in active do
            nodes
          else
            true =
              child["status"] == "completed" or
                (version == 11 and child["status"] in ~w(failed cancelled))

            {parent_token, parent} =
              Enum.find(nodes, fn {_, n} ->
                n.run_id == child["parent_run_id"]
              end)

            closed_token = make_ref()

            closed = %{
              parent
              | token: closed_token,
                run_id: id,
                parent_run_id: parent.run_id,
                ancestors: parent.ancestors ++ [closed_token],
                active: false,
                structural: false,
                owner: nil,
                monitor: nil,
                guardian: nil,
                estimator: nil,
                estimator_model_id: nil,
                approve: nil,
                permissions: nil,
                permission_floor: nil,
                permission_floors: [],
                deadline: nil,
                logical_deadline_at: frame["authority"][id]["deadline_at"]
            }

            true = parent_token in parent.ancestors
            Map.put(nodes, closed_token, closed)
          end
        end)

      ExAgent.Continuation.ScopeLedger.restore(%{state | nodes: nodes}, frame["scope"])
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  defp composition_depth(frame, id) do
    if id == frame["run_id"],
      do: 0,
      else: 1 + composition_depth(frame, frame["children"][id]["parent_run_id"])
  end

  defp composition_candidate(state, owner, token, %{"frame_version" => version} = frame)
       when version in [10, 11],
       do: structural_candidate(state, owner, token, frame)

  defp composition_candidate(state, owner, token, frame) do
    with true <- owner == state.owner and token == state.root,
         {:ok, %{structural: true} = root} <- active_node(state, token),
         true <- state.operations == %{} and state.tool_receipts == %{},
         true <- state.batch_counts == %{} and state.retry_batches == %{},
         true <- MapSet.size(state.batches) == 0,
         :ok <- ExAgent.Continuation.Frame.validate(frame),
         true <- frame["frame_version"] in [7, 8, 9] and frame["run_id"] == root.run_id,
         children = frame["children"],
         running = for({id, c} <- children, c["status"] == "running", do: id),
         true <- length(running) <= 1,
         true <-
           Enum.sort(Enum.map(state.nodes, fn {_, n} -> n.run_id end)) ==
             Enum.sort([root.run_id | running]),
         true <-
           Enum.all?(state.nodes, fn {_, n} ->
             n.active and n.requests == 0 and n.tools == 0 and
               (n.token == token or (not n.structural and n.parent_run_id == root.run_id))
           end) do
      nodes =
        Enum.reduce(children, state.nodes, fn
          {id, %{"status" => "completed"}}, nodes ->
            closed_token = make_ref()

            closed = %{
              root
              | token: closed_token,
                run_id: id,
                parent_run_id: root.run_id,
                ancestors: [token, closed_token],
                active: false,
                structural: false,
                owner: nil,
                monitor: nil,
                guardian: nil,
                estimator: nil,
                estimator_model_id: nil,
                approve: nil,
                permissions: nil,
                permission_floor: nil,
                permission_floors: [],
                deadline: nil,
                logical_deadline_at: frame["authority"][id]["deadline_at"]
            }

            Map.put(nodes, closed_token, closed)

          _, nodes ->
            nodes
        end)

      ExAgent.Continuation.ScopeLedger.restore(%{state | nodes: nodes}, frame["scope"])
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

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
      structural: false,
      ancestors: if(parent, do: parent.ancestors, else: []) ++ [token],
      limits: Keyword.get(opts, :usage_limits) || %UsageLimits{},
      estimator: estimator,
      estimator_model_id: estimator_model_id,
      permissions: Keyword.get(opts, :permissions),
      permission_floor: Keyword.get(opts, :permission_floor),
      permission_floors: Keyword.get(opts, :permission_floors, []),
      approve: Keyword.get(opts, :approve),
      deadline: deadline,
      logical_deadline_at: logical_deadline(opts, parent),
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
    with {:ok, node} <- effect_node(state, token) do
      check_ancestors(state, node, fn ancestor ->
        total = totals(state, ancestor.token)

        with :ok <- Retention.usage_error(total.usage),
             :ok <-
               if(ancestor.requests == 0,
                 do: :ok,
                 else: UsageLimits.check_accounting(ancestor.limits, total.usage)
               ) do
          UsageLimits.check_before_request(
            ancestor.limits,
            total.usage,
            ancestor.requests,
            threshold_cost(ancestor.limits, total)
          )
        end
      end)
    end
  end

  defp effect_node(state, token) do
    with {:ok, node} <- active_node(state, token),
         :ok <- executable_node(node),
         do: {:ok, node}
  end

  defp executable_node(%{structural: true}), do: {:error, :structural_scope_effect}
  defp executable_node(_), do: :ok

  defp resource_check(state, node) do
    check_ancestors(state, node, fn ancestor ->
      total = totals(state, ancestor.token)

      with :ok <- Retention.usage_error(total.usage),
           :ok <- UsageLimits.check_accounting(ancestor.limits, total.usage) do
        UsageLimits.check_before_request(
          %{ancestor.limits | request_limit: nil},
          total.usage,
          0,
          threshold_cost(ancestor.limits, total)
        )
      end
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

    usage = operations |> Enum.map(&priced_usage(&1, token)) |> Usage.sum()
    {usage, _} = Retention.usage(usage)
    known? = Enum.all?(operations, & &1.complete) and Usage.complete?(usage)
    cost = Usage.estimated_cost(usage)
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

  defp estimate(descriptors, model, usage) do
    {costs, error} =
      Enum.reduce(descriptors, {%{}, nil}, fn descriptor, {costs, error} ->
        estimate =
          cond do
            descriptor.estimator == nil ->
              case Usage.estimated_cost(usage) do
                cost when is_number(cost) -> {:ok, cost}
                _ -> :unknown
              end

            not Usage.complete?(usage) ->
              :unknown

            is_function(descriptor.estimator, 1) and descriptor.model_id != identity(model) ->
              :unknown

            true ->
              CostGuard.estimate(descriptor.estimator, model, usage)
          end

        {cost, current_error} =
          case estimate do
            {:ok, cost} ->
              {bounded, error} =
                usage
                |> Usage.with_cost(cost, cost_source(descriptor.estimator, usage))
                |> Retention.usage()

              {Usage.estimated_cost(bounded), error}

            :unknown ->
              {nil, nil}

            {:error, reason} ->
              {nil, if(descriptor.limits.accounting == :strict, do: reason)}
          end

        qualified =
          Usage.with_cost(usage, cost, cost_source(descriptor.estimator, usage))

        current_error =
          current_error ||
            case UsageLimits.check_accounting(descriptor.limits, qualified) do
              :ok -> nil
              {:error, reason} -> reason
            end

        {Map.put(costs, descriptor.token, cost), error || current_error}
      end)

    cond do
      error == nil -> {:ok, costs}
      true -> {:error, error, costs}
    end
  end

  defp accounting_preflight(descriptors, model) do
    Enum.reduce_while(descriptors, :ok, fn descriptor, :ok ->
      limits = descriptor.limits

      cond do
        not UsageLimits.metric_limits?(limits) ->
          {:cont, :ok}

        limits.accounting == :estimated and not descriptor.bounded ->
          {:halt, {:error, :estimated_accounting_requires_request_limit}}

        limits.accounting == :strict and Model.profile(model).accounting_quality == :normalized ->
          {:halt,
           {:error,
            {:accounting_unavailable, hd(UsageLimits.dimensions(limits)), :normalized_only}}}

        limits.accounting == :strict and limits.max_budget_cents != nil and
            descriptor.estimator == nil ->
          {:halt, {:error, :cost_estimator_required}}

        limits.accounting == :strict and limits.max_budget_cents != nil and
          is_function(descriptor.estimator, 1) and descriptor.model_id != identity(model) ->
          {:halt, {:error, :cost_estimator_required}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp threshold_cost(%UsageLimits{accounting: :estimated}, total),
    do: get_in(total.usage.accounting, ["cost", "subtotal_cents"])

  defp threshold_cost(_, total), do: total.cost_cents

  defp priced_usage(%{restored_usage: usage}, _token), do: usage

  defp priced_usage(%{restored_usages: usages}, token), do: Map.fetch!(usages, token)

  defp priced_usage(operation, token) do
    descriptor = Enum.find(Map.get(operation, :descriptors, []), &(&1.token == token))
    source = cost_source(descriptor && descriptor.estimator, operation.usage)

    usage =
      if Map.get(operation, :finalized, true),
        do: operation.usage,
        else: Usage.partial(operation.usage)

    cost_complete? =
      Map.get(operation, :finalized, true) and
        Map.get(operation, :terminal_usage, operation.usage) != nil and
        cost_evidence?(descriptor, operation.usage)

    usage
    |> Usage.with_cost(Map.get(operation.costs, token), source, cost_complete?)
    |> Retention.usage()
    |> elem(0)
  end

  defp operation_key(id) when is_binary(id), do: ["model", id]
  defp operation_key({:tool_usage, _, {request, call}}), do: ["tool", request, call]

  defp operation_key({:tool_usage, _, {request, call, attempt}}),
    do: ["tool", request, call, attempt]

  defp restore_ledger(data, run_id, token) do
    alias ExAgent.Continuation.Record

    with true <- Record.exact?(data, ~w(scope_version run_id requests tools operations batches)),
         true <- data["scope_version"] == 1 and data["run_id"] == run_id,
         true <- Record.counter?(data["requests"]) and Record.counter?(data["tools"]),
         true <- is_list(data["operations"]) and is_map(data["batches"]),
         true <-
           Enum.all?(data["batches"], fn {id, count} ->
             Record.text?(id) and Record.counter?(count)
           end),
         true <- Enum.sum(Map.values(data["batches"])) == data["tools"] do
      operations =
        Enum.map(data["operations"], fn item ->
          true = Record.exact?(item, ~w(id usage complete)) and is_boolean(item["complete"])

          key =
            case item["id"] do
              ["model", id] when is_binary(id) ->
                id

              ["tool", request, call] when is_binary(request) and is_binary(call) ->
                {:tool_usage, token, {request, call}}
            end

          usage = Usage.from_map!(item["usage"])
          :ok = Usage.validate(usage)
          :ok = Retention.usage_error(usage)

          {key,
           %{
             token: token,
             ancestors: [token],
             restored_usage: usage,
             usage: usage,
             costs: %{},
             complete: item["complete"],
             active: false,
             finalized: true,
             terminal_usage: usage,
             record_result: :ok
           }}
        end)

      true = length(operations) == map_size(Map.new(operations))
      true = Enum.count(operations, fn {key, _} -> is_binary(key) end) == data["requests"]
      {:ok, Map.new(operations), data["batches"]}
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  defp accounting_check(descriptors, usage, costs, complete?) do
    Enum.reduce_while(descriptors, :ok, fn descriptor, :ok ->
      qualified =
        Usage.with_cost(
          usage,
          Map.get(costs, descriptor.token),
          cost_source(descriptor.estimator, usage),
          complete? and cost_evidence?(descriptor, usage)
        )

      case UsageLimits.check_accounting(descriptor.limits, qualified) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # A sparse cumulative report cannot erase a previously priced subtotal. A
  # fresh explicit estimate (including zero/unknown/error) still takes precedence.
  defp preserve_cost_subtotals(descriptors, usage, costs, previous) do
    Enum.reduce(descriptors, costs, fn descriptor, acc ->
      if is_nil(acc[descriptor.token]) and not cost_evidence?(descriptor, usage),
        do: Map.put(acc, descriptor.token, previous[descriptor.token]),
        else: acc
    end)
  end

  defp cost_evidence?(%{estimator: estimator}, usage) when is_function(estimator),
    do: Usage.complete?(usage)

  defp cost_evidence?(_, usage), do: is_number(Usage.estimated_cost(usage))

  defp cost_source(nil, usage), do: Usage.qualify(usage).accounting["cost"]["source"]
  defp cost_source(_, _), do: "estimator"

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
         true <- is_list(Keyword.get(opts, :permission_floors, [])),
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

  defp logical_deadline(opts, parent) do
    # Only a leaf distinguishes its host logical deadline from the Writer's
    # attempt/lease deadline. A root must capture the deadline actually applied.
    deadline =
      if parent, do: Keyword.get(opts, :logical_deadline, opts[:deadline]), else: opts[:deadline]

    utc =
      if deadline,
        do:
          max(
            0,
            System.system_time(:millisecond) + deadline - System.monotonic_time(:millisecond)
          )

    minimum(utc, if(parent, do: parent.logical_deadline_at))
  end

  defp validate_usage(nil), do: :ok

  defp validate_usage(%Usage{} = usage), do: Usage.validate(usage)

  defp validate_usage(_), do: {:error, :invalid_model_usage}

  defp complete_usage?(%Usage{input_tokens: input, output_tokens: output}),
    do: is_integer(input) and is_integer(output)

  defp complete_usage?(_), do: false

  defp preserve_reported_usage(previous, nil), do: previous
  defp preserve_reported_usage(nil, usage), do: usage

  defp preserve_reported_usage(previous, usage),
    do: %Usage{
      Usage.qualify(usage)
      | input_tokens: usage.input_tokens || previous.input_tokens,
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
end

defmodule ExAgent.Continuation.ScopeLedger do
  @moduledoc false
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.Usage
  alias ExAgent.Retention

  # Validate the portable graph before invoking any host model/tool rehydrator.
  # These synthetic tokens are used only by the data validator; they never become
  # executable handles or supply authority to ExecutionScope.restore_tree/2.
  def validate(data) do
    with %{"scope_version" => 2, "root_run_id" => root, "nodes" => nodes} <- data,
         true <- is_map(nodes) and Map.has_key?(nodes, root),
         true <- Enum.all?(Map.keys(nodes), &valid_path?(&1, nodes, MapSet.new())),
         state = %{
           root: root,
           nodes:
             Map.new(nodes, fn {id, node} ->
               {id,
                %{
                  run_id: id,
                  parent_run_id: node["parent_run_id"],
                  ancestors: path(id, nodes),
                  requests: 0,
                  tools: 0
                }}
             end),
           operations: %{},
           batches: MapSet.new(),
           batch_counts: %{},
           retry_batches: %{}
         },
         {:ok, _} <- restore(state, data) do
      :ok
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  # A node's cursor counts its own model requests/batches, whereas the tree ledger
  # counts descendant admissions at every ancestor. Never flatten the latter into
  # a root run_step or add children's already-priced usage again.
  def node_position(%{"scope_version" => 2} = data, run_id) do
    with :ok <- validate(data), true <- Map.has_key?(data["nodes"], run_id) do
      requests =
        Enum.count(data["operations"], fn op ->
          op["run_id"] == run_id and match?(["model", _], op["id"])
        end)

      batches =
        for batch <- data["batches"],
            batch["run_id"] == run_id,
            into: %{},
            do: {batch["id"], batch["count"]}

      {:ok, %{requests: requests, batches: batches}}
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  end

  def node_data(data, run_id) do
    with {:ok, position} <- node_position(data, run_id) do
      operations =
        for op <- data["operations"], op["run_id"] == run_id do
          %{"id" => op["id"], "usage" => op["ancestors"][run_id], "complete" => op["complete"]}
        end

      {:ok,
       %{
         "scope_version" => 1,
         "run_id" => run_id,
         "requests" => position.requests,
         "tools" =>
           Enum.sum(Map.values(position.batches)) +
             Enum.count(Map.get(data, "retry_batches", []), &(&1["run_id"] == run_id)),
         "operations" => operations,
         "batches" => position.batches
       }}
    end
  end

  def reconcile_request(data, run_id, request_id, usage, accounting \\ nil) do
    {tree, legacy?} = as_tree(data)

    with :ok <- validate(tree),
         %{} = operation <-
           Enum.find(
             tree["operations"],
             &(&1["run_id"] == run_id and &1["id"] == ["model", request_id])
           ),
         usage = Usage.qualify(usage),
         :ok <- Usage.validate(usage),
         :ok <- Retention.usage_error(usage),
         true <-
           not operation["complete"] or
             without_cost(operation["usage"]) === without_cost(Usage.to_map(usage)),
         {:ok, ancestors} <- reconciled_prices(operation, Usage.to_map(usage), accounting) do
      updated = %{
        operation
        | "usage" => Usage.to_map(usage),
          "terminal_usage" => Usage.to_map(usage),
          "complete" => Usage.complete?(usage),
          "ancestors" => ancestors
      }

      tree =
        Map.update!(tree, "operations", fn operations ->
          Enum.map(
            operations,
            &if(&1["id"] == ["model", request_id] and &1["run_id"] == run_id,
              do: updated,
              else: &1
            )
          )
        end)

      with :ok <- validate(tree) do
        if legacy? do
          node_data(tree, run_id)
        else
          {:ok, tree}
        end
      end
    else
      _ -> {:error, :invalid_reconciled_accounting}
    end
  rescue
    _ -> {:error, :invalid_reconciled_accounting}
  end

  def usage(data, run_id) do
    {tree, _} = as_tree(data)

    usages =
      for op <- tree["operations"],
          Map.has_key?(op["ancestors"], run_id),
          do: decode_usage(op["ancestors"][run_id])

    total = Usage.sum(usages)
    with :ok <- Retention.usage_error(total), do: {:ok, total}
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  defp as_tree(%{"scope_version" => 2} = data),
    do: {Map.put_new(data, "retry_batches", []), false}

  defp as_tree(%{"scope_version" => 1, "run_id" => id} = data) do
    tree = %{
      "scope_version" => 2,
      "root_run_id" => id,
      "nodes" => %{
        id => %{"parent_run_id" => nil, "requests" => data["requests"], "tools" => data["tools"]}
      },
      "operations" =>
        Enum.map(data["operations"], fn op ->
          Map.merge(op, %{
            "run_id" => id,
            "terminal_usage" => op["usage"],
            "ancestors" => %{id => op["usage"]}
          })
        end),
      "batches" =>
        Enum.map(data["batches"], fn {request, count} ->
          %{"id" => request, "run_id" => id, "count" => count}
        end)
    }

    {Map.put(tree, "retry_batches", []), true}
  end

  defp without_cost(nil), do: nil
  defp without_cost(usage), do: update_in(usage, ["accounting"], &Map.delete(&1, "cost"))

  defp reconciled_prices(operation, usage, nil) do
    prices =
      Map.new(operation["ancestors"], fn {id, previous} ->
        cost = previous["accounting"]["cost"]

        cost =
          if operation["complete"] or is_nil(cost["subtotal_cents"]),
            do: cost,
            else: cost |> Map.put("cents", nil) |> Map.put("availability", "partial")

        {id, put_in(usage, ["accounting", "cost"], cost)}
      end)

    {:ok, prices}
  end

  defp reconciled_prices(operation, usage, prices) when is_map(prices) do
    valid? =
      Enum.sort(Map.keys(prices)) == Enum.sort(Map.keys(operation["ancestors"])) and
        Enum.all?(prices, fn {id, data} ->
          value = Usage.from_map!(data)

          Usage.validate(value) == :ok and Retention.usage_error(value) == :ok and
            without_cost(data) === without_cost(usage) and
            (not operation["complete"] or
               data["accounting"]["cost"] === operation["ancestors"][id]["accounting"]["cost"])
        end)

    if valid?, do: {:ok, prices}, else: {:error, :invalid_reconciled_accounting}
  end

  defp reconciled_prices(_, _, _), do: {:error, :invalid_reconciled_accounting}

  # Configuration, permissions and live ownership are supplied by the trusted
  # rehydrator. This codec only restores accounting into that exact tree.
  def export(state, priced) do
    nodes =
      Map.new(state.nodes, fn {_, node} ->
        {node.run_id,
         %{
           "parent_run_id" => node.parent_run_id,
           "requests" => node.requests,
           "tools" => node.tools
         }}
      end)

    operations =
      Enum.map(state.operations, fn {id, operation} ->
        %{
          "id" => encode_id(id),
          "run_id" => state.nodes[operation.token].run_id,
          "usage" => usage_data(operation.usage),
          "terminal_usage" => usage_data(Map.get(operation, :terminal_usage, operation.usage)),
          "complete" => operation.complete,
          "ancestors" =>
            Map.new(operation.ancestors, fn token ->
              {state.nodes[token].run_id, Usage.to_map(priced.(operation, token))}
            end)
        }
      end)

    batches =
      Enum.map(state.batch_counts, fn {id, count} ->
        operation = Map.fetch!(state.operations, id)
        %{"id" => id, "run_id" => state.nodes[operation.token].run_id, "count" => count}
      end)

    data = %{
      "scope_version" => 2,
      "root_run_id" => state.nodes[state.root].run_id,
      "nodes" => nodes,
      "operations" => operations,
      "batches" => batches,
      "retry_batches" =>
        Enum.map(state.retry_batches, fn {id, batch} ->
          %{
            "id" => id,
            "run_id" => state.nodes[batch.token].run_id,
            "request_id" => batch.request_id
          }
        end)
    }

    # Use the same integrity checks for emission and import; no executable state
    # escapes the process and partial model operations stay qualified as partial.
    with {:ok, _} <- restore(state, data), do: {:ok, data}
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  def restore(state, data) do
    data = if is_map(data), do: Map.put_new(data, "retry_batches", []), else: data

    with true <-
           Record.exact?(
             data,
             ~w(scope_version root_run_id nodes operations batches retry_batches)
           ),
         true <- data["scope_version"] === 2,
         true <- data["root_run_id"] === state.nodes[state.root].run_id,
         true <-
           is_map(data["nodes"]) and is_list(data["operations"]) and is_list(data["batches"]),
         by_id = Map.new(state.nodes, fn {token, node} -> {node.run_id, token} end),
         true <- map_size(by_id) == map_size(state.nodes),
         true <- Enum.sort(Map.keys(by_id)) == Enum.sort(Map.keys(data["nodes"])),
         true <- valid_nodes?(state, data["nodes"], by_id),
         {:ok, operations} <- operations(data["operations"], state, by_id),
         {:ok, batches} <- batches(data["batches"], operations, by_id),
         {:ok, retries} <- retry_batches(data["retry_batches"], operations, batches, by_id),
         true <- counts_match?(data["nodes"], operations, batches, retries, by_id) do
      nodes =
        Map.new(state.nodes, fn {token, node} ->
          saved = data["nodes"][node.run_id]
          {token, %{node | requests: saved["requests"], tools: saved["tools"]}}
        end)

      {:ok,
       %{
         state
         | nodes: nodes,
           operations: operations,
           batches: MapSet.new(Map.keys(batches)),
           batch_counts: batches,
           retry_batches: retries
       }}
    else
      _ -> {:error, :invalid_scope_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_scope_checkpoint}
  end

  defp valid_nodes?(state, nodes, by_id) do
    Enum.all?(nodes, fn {id, saved} ->
      node = state.nodes[by_id[id]]

      Record.text?(id) and Record.exact?(saved, ~w(parent_run_id requests tools)) and
        saved["parent_run_id"] === node.parent_run_id and
        Record.counter?(saved["requests"]) and Record.counter?(saved["tools"]) and
        valid_path?(id, nodes, MapSet.new()) and
        Enum.map(node.ancestors, &state.nodes[&1].run_id) == path(id, nodes)
    end) and Enum.count(nodes, fn {_, n} -> is_nil(n["parent_run_id"]) end) == 1
  end

  defp valid_path?(nil, _, _), do: true

  defp valid_path?(id, nodes, seen) do
    Map.has_key?(nodes, id) and not MapSet.member?(seen, id) and
      valid_path?(nodes[id]["parent_run_id"], nodes, MapSet.put(seen, id))
  end

  defp path(nil, _), do: []
  defp path(id, nodes), do: path(nodes[id]["parent_run_id"], nodes) ++ [id]

  defp operations(items, state, by_id) do
    pairs =
      Enum.map(items, fn item ->
        true = Record.exact?(item, ~w(id run_id usage terminal_usage complete ancestors))
        true = is_boolean(item["complete"])
        token = Map.fetch!(by_id, item["run_id"])
        node = state.nodes[token]
        # Only the trusted rehydrator chooses structural roots. Scope2 remains a
        # ledger, not execution authority: old agent roots can own operations,
        # but importing their operations into a model-less host must fail closed.
        false = Map.get(node, :structural, false)
        key = decode_id(item["id"], token)
        ancestor_ids = Enum.map(node.ancestors, &state.nodes[&1].run_id)
        true = Enum.sort(Map.keys(item["ancestors"])) == Enum.sort(ancestor_ids)

        usages =
          Map.new(item["ancestors"], fn {id, usage} ->
            {Map.fetch!(by_id, id), decode_usage(usage)}
          end)

        {key,
         %{
           token: token,
           ancestors: node.ancestors,
           usage: decode_usage(item["usage"]),
           terminal_usage: decode_usage(item["terminal_usage"]),
           restored_usages: usages,
           costs: %{},
           complete: item["complete"],
           active: false,
           finalized: true,
           record_result: :ok
         }}
      end)

    true = length(pairs) == map_size(Map.new(pairs))
    {:ok, Map.new(pairs)}
  end

  defp batches(items, operations, by_id) do
    pairs =
      Enum.map(items, fn item ->
        true = Record.exact?(item, ~w(id run_id count))
        true = Record.text?(item["id"]) and Record.counter?(item["count"])
        token = Map.fetch!(by_id, item["run_id"])
        %{token: ^token} = Map.fetch!(operations, item["id"])
        {item["id"], item["count"]}
      end)

    true = length(pairs) == map_size(Map.new(pairs))
    {:ok, Map.new(pairs)}
  end

  defp retry_batches(items, operations, batches, by_id) do
    pairs =
      Enum.map(items, fn item ->
        true = Record.exact?(item, ~w(id run_id request_id)) and Record.text?(item["id"])
        token = Map.fetch!(by_id, item["run_id"])
        %{token: ^token} = Map.fetch!(operations, item["request_id"])
        true = Map.has_key?(batches, item["request_id"])
        {item["id"], %{token: token, request_id: item["request_id"]}}
      end)

    true = length(pairs) == map_size(Map.new(pairs))
    {:ok, Map.new(pairs)}
  end

  defp counts_match?(nodes, operations, batches, retries, by_id) do
    Enum.all?(nodes, fn {id, saved} ->
      token = by_id[id]

      requests =
        Enum.count(operations, fn {key, op} -> is_binary(key) and token in op.ancestors end)

      tools =
        Enum.reduce(batches, 0, fn {key, count}, total ->
          if token in operations[key].ancestors, do: total + count, else: total
        end)

      tools =
        tools +
          Enum.count(retries, fn {_, batch} -> token in operations[batch.request_id].ancestors end)

      saved["requests"] === requests and saved["tools"] === tools
    end)
  end

  defp encode_id(id) when is_binary(id), do: ["model", id]
  defp encode_id({:tool_usage, _, {request, call}}), do: ["tool", request, call]
  defp encode_id({:tool_usage, _, {request, call, attempt}}), do: ["tool", request, call, attempt]

  defp decode_id(["model", id], _) do
    true = Record.text?(id)
    id
  end

  defp decode_id(["tool", request, call], token) do
    true = Record.text?(request) and Record.text?(call)
    {:tool_usage, token, {request, call}}
  end

  defp decode_id(["tool", request, call, attempt], token) do
    true = Record.text?(request) and Record.text?(call) and Record.text?(attempt)
    {:tool_usage, token, {request, call, attempt}}
  end

  defp usage_data(nil), do: nil
  defp usage_data(usage), do: Usage.to_map(usage)
  defp decode_usage(nil), do: nil

  defp decode_usage(data) do
    usage = Usage.from_map!(data)
    :ok = Usage.validate(usage)
    :ok = Retention.usage_error(usage)
    usage
  end
end

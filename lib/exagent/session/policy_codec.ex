defmodule ExAgent.Session.PolicyCodec do
  @moduledoc false
  alias ExAgent.Session.TurnPolicy.{RoundRobin, Initiative, SupervisorPolicy}
  @builtins [RoundRobin, Initiative, SupervisorPolicy]

  def dump(%mod{} = state) when mod in @builtins,
    do: {:ok, 1, Map.from_struct(state)}

  def dump(%mod{} = state) do
    with :ok <- load_trusted_policy(mod) do
      if function_exported?(mod, :snapshot, 1),
        do: mod.snapshot(state),
        else: {:error, :unsupported_policy_snapshot}
    end
  end

  def restore(mod, 1, data, context) when mod in [RoundRobin, Initiative] and is_map(data) do
    ids = data["ids"]
    index = data["index"]
    current = data["current"]

    if valid_ids?(ids, context) and MapSet.new(ids) == roster(context) and
         ExAgent.SnapshotData.counter?(index) and (is_nil(current) or current in ids) do
      {:ok, struct(mod, ids: ids, index: cursor(index, length(ids)), current: current)}
    else
      {:error, :invalid_policy_state}
    end
  end

  def restore(SupervisorPolicy, 1, data, context) when is_map(data) do
    workers = data["workers"]
    supervisor = data["supervisor"]
    index = data["worker_index"]
    current = data["current"]

    if valid_ids?(workers, context) and ExAgent.SnapshotData.counter?(index) and
         (is_nil(supervisor) or MapSet.member?(roster(context), supervisor)) and
         supervisor not in workers and is_boolean(data["emit_supervisor_next"]) and
         (is_nil(current) or MapSet.member?(roster(context), current)) do
      {:ok,
       %SupervisorPolicy{
         workers: workers,
         supervisor: supervisor,
         worker_index: cursor(index, length(workers)),
         current: current,
         emit_supervisor_next: data["emit_supervisor_next"]
       }}
    else
      {:error, :invalid_policy_state}
    end
  end

  def restore(mod, version, data, context) when mod not in @builtins do
    with :ok <- load_trusted_policy(mod) do
      if function_exported?(mod, :restore_snapshot, 3) do
        case mod.restore_snapshot(version, data, context) do
          {:ok, %^mod{} = state} -> {:ok, state}
          {:error, _} = error -> error
          _ -> {:error, :invalid_policy_state}
        end
      else
        {:error, :unsupported_policy_snapshot}
      end
    end
  end

  def restore(_, _, _, _), do: {:error, :invalid_policy_state}

  # Only the runtime's configured policy reaches here; never resolve JSON names.
  defp load_trusted_policy(mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} -> :ok
      {:error, reason} -> {:error, {:policy_module_unavailable, mod, reason}}
    end
  end

  # Keep the end-of-round boundary, so a newly appended participant gets a turn.
  def cursor(_, 0), do: 0
  def cursor(0, _), do: 0
  def cursor(index, count), do: rem(index - 1, count) + 1

  defp valid_ids?(ids, context) when is_list(ids),
    do:
      length(ids) == MapSet.size(MapSet.new(ids)) and
        Enum.all?(ids, &MapSet.member?(roster(context), &1))

  defp valid_ids?(_, _), do: false
  defp roster(context), do: MapSet.new(context.participants, & &1.id)
end

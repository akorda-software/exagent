defmodule ExAgent.Continuation.Approval do
  @moduledoc false
  alias ExAgent.Continuation.Record
  alias ExAgent.Tool.JSON

  @binding ~w(approval_version id run_id call_id tool_name args schema_hash definition policy requested_revision)
  @fields @binding ++ ~w(payload_hash decision)

  def new(attributes) do
    with {:ok, attributes} <- JSON.normalize(attributes),
         binding = Map.put(attributes, "approval_version", 1),
         true <- binding?(binding),
         {:ok, hash} <- Record.digest(binding) do
      {:ok, Map.merge(binding, %{"payload_hash" => hash, "decision" => nil})}
    else
      _ -> {:error, :invalid_approval}
    end
  end

  def valid?(approval) when is_map(approval) do
    binding = Map.take(approval, @binding)

    Record.exact?(approval, @fields) and binding?(binding) and
      Record.digest(binding) == {:ok, approval["payload_hash"]} and
      decision?(approval["decision"])
  end

  def valid?(_), do: false

  def collection?(approvals) when is_map(approvals) and map_size(approvals) in 1..256,
    do: Enum.all?(approvals, fn {id, approval} -> valid?(approval) and approval["id"] == id end)

  def collection?(_), do: false

  def pending_count(progress) do
    case Map.get(progress, "approvals", %{}) do
      approvals when is_map(approvals) ->
        Enum.count(approvals, fn {_, approval} ->
          is_map(approval) and is_nil(approval["decision"])
        end)

      _ ->
        0
    end
  end

  def approved?(approval), do: match?(%{"action" => "approve"}, approval["decision"])

  defp binding?(b) do
    Record.exact?(b, @binding) and b["approval_version"] == 1 and
      Enum.all?(~w(id run_id call_id tool_name), &Record.text?(b[&1])) and
      is_map(b["args"]) and Record.reference?(b["definition"]) and
      Record.reference?(b["policy"]) and Record.positive?(b["requested_revision"]) and
      is_binary(b["schema_hash"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, b["schema_hash"])
  end

  defp decision?(nil), do: true

  defp decision?(decision),
    do:
      Record.exact?(decision, ~w(action actor_id at)) and
        decision["action"] in ~w(approve deny) and Record.text?(decision["actor_id"]) and
        Record.timestamp?(decision["at"])
end

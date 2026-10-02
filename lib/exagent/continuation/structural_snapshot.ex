defmodule ExAgent.Continuation.StructuralSnapshot do
  @moduledoc false
  alias ExAgent.Continuation.{Frame, Record}
  alias ExAgent.Coordination.Composition

  # Root identity only, never an agent snapshot. Execution progress belongs to
  # the explicitly versioned frame; this snapshot cannot authorize a leaf.
  def new(id, frame) do
    %{
      "composition_snapshot_version" => 1,
      "composition_id" => id,
      "run_id" => frame["run_id"],
      "revision" => 0,
      "binding" => frame["binding"]
    }
  end

  def validate(data, {_, :agent, id}) do
    with true <-
           Record.exact?(
             data,
             ~w(composition_snapshot_version composition_id run_id revision binding)
           ),
         true <- data["composition_snapshot_version"] === 1,
         true <- data["composition_id"] === id and Record.text?(id),
         true <- Record.text?(data["run_id"]) and data["revision"] === 0,
         :ok <- Composition.validate_stored(data["binding"]) do
      {:ok, data}
    else
      _ -> {:error, :invalid_structural_snapshot}
    end
  end

  def validate(_, _), do: {:error, :invalid_structural_snapshot}

  def consistent?(snapshot, execution) do
    frame = execution["progress"]["runtime"]

    Frame.validate(frame) == :ok and
      snapshot["run_id"] === execution["run_id"] and
      frame["run_id"] === execution["run_id"] and
      snapshot["binding"] === frame["binding"] and
      execution["definition"] === Map.take(frame["binding"], ~w(id version))
  end
end

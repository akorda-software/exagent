defmodule ExAgent.Session.Continuations do
  @moduledoc false
  alias ExAgent.{Continuation, Retention, SnapshotData, Store}
  alias ExAgent.Continuation.Record

  @max_bindings 64
  @reference_fields ~w(version participant_id namespace id record_id run_id revision)
  @terminal [:completed, :denied, :cancelled, :expired]

  def bindings(bindings, participants)
      when is_map(bindings) and map_size(bindings) <= @max_bindings do
    valid =
      Enum.all?(bindings, fn {id, binding} ->
        SnapshotData.id?(id) and Retention.bytes(id) <= 512 and Map.has_key?(participants, id) and
          match?(%{store: %Store.Scope{}, id: _}, binding) and Record.text?(binding.id) and
          Store.capabilities(binding.store).continuation == :atomic
      end)

    if valid, do: :ok, else: {:error, :invalid_session_continuations}
  rescue
    _ -> {:error, :invalid_session_continuations}
  end

  def bindings(_, _), do: {:error, :invalid_session_continuations}

  def dump(state) do
    Enum.map(Map.get(state, :continuation_bindings, %{}), fn {id, binding} ->
      Map.merge(entry(state, id), %{"participant_id" => id, "binding" => binding_data(binding)})
    end)
  end

  def valid_data?(data) when is_list(data) and length(data) <= @max_bindings do
    data = normalize_data(data)

    Enum.all?(data, fn item ->
      Record.exact?(item, ~w(participant_id binding pending consumed error diagnostic_id)) and
        SnapshotData.id?(item["participant_id"]) and binding_valid?(item["binding"]) and
        (is_nil(item["pending"]) or
           (reference?(item["pending"]) and
              item["pending"]["participant_id"] === item["participant_id"] and
              Map.take(item["pending"], ~w(namespace id)) === item["binding"])) and
        (is_nil(item["consumed"]) or consumed?(item["consumed"])) and
        item["error"] in [
          nil,
          "unavailable",
          "identity_changed",
          "result_not_final",
          "changed_during_callback"
        ] and
        ((is_nil(item["error"]) and is_nil(item["diagnostic_id"])) or
           (not is_nil(item["error"]) and Record.text?(item["diagnostic_id"]))) and
        Retention.bytes(item) <= 8192
    end) and length(data) == MapSet.size(MapSet.new(data, & &1["participant_id"]))
  rescue
    _ -> false
  end

  def valid_data?(_), do: false

  def normalize_data(data) when is_list(data) do
    Enum.map(data, fn item ->
      if is_map(item) and is_nil(item["error"]),
        do: Map.put_new(item, "diagnostic_id", nil),
        else: item
    end)
  end

  def normalize_data(data), do: data

  def restore(state, data, version) do
    data = normalize_data(data)

    with :ok <- validate_bindings(state, data, version) do
      entries =
        Map.new(
          data,
          &{&1["participant_id"], Map.take(&1, ~w(pending consumed error diagnostic_id))}
        )

      {:ok, %{state | continuation_state: entries} |> refresh()}
    end
  end

  def validate_bindings(state, data, version) do
    data = normalize_data(data)

    same_bindings? =
      version != 3 or
        Enum.sort(Enum.map(data, & &1["participant_id"])) ==
          Enum.sort(Map.keys(state.continuation_bindings))

    if valid_data?(data) and same_bindings? and
         Enum.all?(data, fn item ->
           binding = state.continuation_bindings[item["participant_id"]]
           binding && binding_data(binding) == item["binding"]
         end) do
      :ok
    else
      {:error, :session_continuation_binding_changed}
    end
  end

  def query(state, id) do
    case Map.fetch(state.continuation_bindings, id) do
      {:ok, binding} ->
        with {:ok, result} <- inspect_binding(id, binding) do
          {:ok, Map.put(result, :witness, witness(state, id, result.reference))}
        end

      :error ->
        {:error, :continuation_not_configured}
    end
  end

  def refresh(state) do
    Enum.reduce(state.continuation_bindings, state, fn {id, binding}, current ->
      old = entry(current, id)

      next =
        case inspect_binding(id, binding) do
          {:ok, %{reference: nil}} ->
            cond do
              old["pending"] -> unavailable(old)
              old["error"] == "unavailable" -> clear_unavailable(old)
              true -> old
            end

          {:ok, %{reference: ref, status: status}} ->
            cond do
              old["pending"] && identity(old["pending"]) != identity(ref) ->
                diagnostic(old, "identity_changed")

              identity(old["consumed"]) == identity(ref) and status in @terminal ->
                old |> Map.put("pending", nil) |> clear_unavailable()

              true ->
                old |> Map.put("pending", ref) |> clear_unavailable()
            end

          {:error, _} ->
            unavailable(old)
        end

      put_in(current.continuation_state[id], next)
    end)
  end

  def blocked(state, except \\ nil) do
    Enum.find_value(state.continuation_bindings, fn {id, _} ->
      item = entry(state, id)

      if id != except and (item["pending"] || item["error"]),
        do: {:session_continuation_pending, id, item["error"] || "completion_required"}
    end)
  end

  def bound?(state, id), do: Map.has_key?(state.continuation_bindings, id)

  def detach(state, id) do
    case Map.fetch(state.continuation_bindings, id) do
      :error ->
        {:ok, state}

      {:ok, binding} ->
        %{"pending" => pending, "error" => local_error} = entry(state, id)

        case inspect_binding(id, binding) do
          {:ok, %{reference: nil, status: :absent}}
          when is_nil(pending) and is_nil(local_error) ->
            {:ok,
             %{
               state
               | continuation_bindings: Map.delete(state.continuation_bindings, id),
                 continuation_state: Map.delete(state.continuation_state, id)
             }}

          {:error, _} = error ->
            error

          _ ->
            {:error, :continuation_binding_retained}
        end
    end
  end

  def nonfinal_result?({:error, %ExAgent.RunError{}}), do: true
  def nonfinal_result?({:error, %ExAgent.CheckpointError{}}), do: true

  def nonfinal_result?({:ok, %{status: status}})
      when status in [:paused, :running, :failed, :cancelled], do: true

  def nonfinal_result?(_), do: false

  def result_failed(state, id) do
    old = entry(state, id)
    put_in(state.continuation_state[id], diagnostic(old, "result_not_final", true))
  end

  def complete(state, id, reference, callback) do
    with {:ok, expected} <- ExAgent.Tool.JSON.normalize(reference),
         true <- reference?(expected) and expected["participant_id"] === id,
         {:ok, %{reference: actual, status: status}} <- query(state, id),
         true <- actual === expected and status in @terminal,
         true <-
           is_nil(entry(state, id)["pending"]) or
             identity(entry(state, id)["pending"]) == identity(actual),
         false <- identity(entry(state, id)["consumed"]) == identity(actual) do
      case callback.() do
        {:ok, shared_state} ->
          case query(state, id) do
            {:ok, %{reference: ^actual, status: ^status}} ->
              consumed = Map.take(actual, ~w(record_id run_id))

              item = %{
                "pending" => nil,
                "consumed" => consumed,
                "error" => nil,
                "diagnostic_id" => nil
              }

              {:ok, shared_state, put_in(state.continuation_state[id], item)}

            _ ->
              item =
                entry(state, id)
                |> Map.put("pending", actual)
                |> diagnostic("changed_during_callback", true)

              {:blocked, :continuation_changed_during_callback,
               put_in(state.continuation_state[id], item)}
          end

        {:error, reason} ->
          {:blocked, reason, state}
      end
    else
      _ -> {:blocked, :invalid_session_continuation_reference, state}
    end
  rescue
    _ -> {:blocked, :invalid_session_continuation_reference, state}
  end

  def reference?(data) do
    Record.exact?(data, @reference_fields) and data["version"] === 1 and
      SnapshotData.id?(data["participant_id"]) and
      Enum.all?(~w(namespace id record_id run_id), &Record.text?(data[&1])) and
      Record.positive?(data["revision"]) and Retention.bytes(data) <= 4096
  end

  def reconcile(state, id, supplied) do
    item = entry(state, id)

    with true <- item["error"] in ["result_not_final", "changed_during_callback"],
         {:ok, expected} <- ExAgent.Tool.JSON.normalize(supplied),
         {:ok, %{reference: reference, status: status, witness: actual}} <- query(state, id),
         true <- not is_nil(actual) and actual === expected and status in @terminal,
         true <- identity(reference) == identity(item["consumed"]),
         true <- is_nil(item["pending"]),
         {:ok, %{reference: ^reference, status: ^status, witness: ^actual}} <- query(state, id) do
      cleared = %{item | "error" => nil, "diagnostic_id" => nil}
      {:ok, put_in(state.continuation_state[id], cleared)}
    else
      _ -> {:error, :invalid_session_reconciliation}
    end
  rescue
    _ -> {:error, :invalid_session_reconciliation}
  end

  defp witness(state, id, reference) do
    item = entry(state, id)

    if not is_nil(item["diagnostic_id"]) and not is_nil(reference) do
      data = %{
        "witness_version" => 1,
        "session_id" => state.session_id,
        "session_namespace" => state.namespace,
        "session_revision" => state.revision,
        "participant_id" => id,
        "diagnostic_id" => item["diagnostic_id"],
        "error" => item["error"],
        "reference" => reference
      }

      if Retention.bytes(data) <= 8192, do: data
    end
  end

  defp unavailable(%{"error" => nil} = item), do: diagnostic(item, "unavailable")
  defp unavailable(item), do: item

  defp clear_unavailable(%{"error" => "unavailable"} = item),
    do: %{item | "error" => nil, "diagnostic_id" => nil}

  defp clear_unavailable(item), do: item

  defp diagnostic(item, error, new? \\ false) do
    if item["error"] == error and not new?,
      do: item,
      else: %{
        item
        | "error" => error,
          "diagnostic_id" =>
            "diagnostic-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
  end

  defp inspect_binding(id, binding) do
    case Continuation.get(binding.store, binding.id) do
      {:ok, %{status: status, record: record}} ->
        reference = %{
          "version" => 1,
          "participant_id" => id,
          "namespace" => binding.store.namespace,
          "id" => binding.id,
          "record_id" => record["record_id"],
          "run_id" => record["execution"]["run_id"],
          "revision" => record["revision"]
        }

        status = if Record.unresolved?(record["execution"]), do: :uncertain, else: status

        if reference?(reference),
          do: {:ok, %{reference: reference, status: status}},
          else: {:error, :invalid_session_continuation_reference}

      {:error, :not_found} ->
        {:ok, %{reference: nil, status: :absent}}

      {:error, _} ->
        {:error, :continuation_unavailable}
    end
  end

  defp binding_data(binding), do: %{"namespace" => binding.store.namespace, "id" => binding.id}

  defp binding_valid?(data),
    do:
      Record.exact?(data, ~w(namespace id)) and Record.text?(data["namespace"]) and
        Record.text?(data["id"])

  defp consumed?(data),
    do: Record.exact?(data, ~w(record_id run_id)) and Enum.all?(Map.values(data), &Record.text?/1)

  defp identity(nil), do: nil
  defp identity(ref), do: {ref["record_id"], ref["run_id"]}

  defp entry(state, id),
    do:
      Map.get(state.continuation_state, id, %{
        "pending" => nil,
        "consumed" => nil,
        "error" => nil,
        "diagnostic_id" => nil
      })
end

defmodule ExAgent.LegacyStructuralFixture do
  @moduledoc false
  alias ExAgent.{ExecutionScope, Store}
  alias ExAgent.Continuation.{Budget, Frame, Record, StructuralSnapshot, Writer}
  alias ExAgent.Coordination.Composition

  # Seed a fresh historical format, not a relabelled live format-10 execution.
  # Every row crosses real CAS and the record codec before public resume.
  def open(run, config) do
    with {:ok, config} <- Writer.config(config),
         {:ok, record} <- create(run, config) do
      Writer.open(run, config, record)
    end
  end

  def run(definition, input, opts) do
    {:ok, binding} = Composition.binding(definition)

    config =
      Map.merge(opts[:continuation], %{
        kind: :composition,
        composition: definition,
        definition: Map.take(binding, ~w(id version))
      })

    {:ok, config} = Writer.config(config)
    bound = Writer.bind_deadline(Keyword.put(opts[:root_options] || [], :continuation, config))
    config = bound[:continuation]
    root_options = Keyword.delete(bound, :continuation)
    utc = System.system_time(:millisecond)
    now = System.monotonic_time(:millisecond)

    logical =
      for key <- [:deadline_at, :expires_at], is_integer(config[key]), do: now + config[key] - utc

    deadline =
      Enum.reduce(logical, root_options[:deadline], &ExAgent.Continuation.Authority.minimum/2)

    root_options = Keyword.put(root_options, :deadline, deadline)
    {:ok, scope} = ExecutionScope.start_structural(id("run"), root_options)

    created =
      try do
        create(%{run_id: scope.run_id, execution_scope: scope, input: input}, config)
      after
        ExecutionScope.stop(scope)
      end

    with {:ok, record} <- created do
      Composition.resume(definition, reference(record, config), opts)
    else
      {:error, reason} ->
        partial =
          Composition.project(definition, nil, config)
          |> Map.merge(%{status: :failed, output: nil, error_step_id: nil, error_phase: :open})

        {:error, %ExAgent.RunError{reason: reason, partial: partial}}
    end
  end

  defp create(run, config) do
    with {:ok, frame} <- Frame.capture_structural(run, config) do
      frame = frame |> Map.delete("frontier") |> Map.put("frame_version", 9)
      :ok = Frame.validate(frame)

      command = %{
        "record_id" => id("record"),
        "operation" => "create",
        "operation_id" => id("operation"),
        "actor_id" => "exagent-runtime",
        "payload" => %{
          "snapshot" => StructuralSnapshot.new(config.id, frame),
          "execution" => %{
            "kind" => "composition",
            "continuation_id" => id("continuation"),
            "run_id" => run.run_id,
            "definition" => config.definition,
            "policy" => config.policy,
            "deadline_at" => config[:deadline_at],
            "expires_at" => config.expires_at,
            "progress" => %{
              "runtime" => frame,
              "active_budget" => Budget.new(config[:active_time_limit_ms])
            }
          }
        }
      }

      with {:ok, %{record: record}} <-
             Store.transition(config.store, :agent, config.id, :absent, command),
           {:ok, bytes} <- Record.encode(record, {config.store.namespace, :agent, config.id}),
           {:ok, ^record} <- Record.decode(bytes, {config.store.namespace, :agent, config.id}) do
        {:ok, record}
      end
    end
  end

  defp reference(record, config),
    do: %{
      version: 1,
      id: config.id,
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"]
    }

  defp id(prefix),
    do: prefix <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end

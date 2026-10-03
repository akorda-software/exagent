# Generic, deterministic R6 recipes. No external provider/database is needed.
# EXAGENT_OFFLINE=1 MIX_ENV=test mix run --no-start examples/coordination_workflows.exs --run
defmodule ExAgent.Examples.CoordinationWorkflows do
  alias ExAgent.{Continuation, Permissions, Store, Tool}
  alias ExAgent.Coordination.{Composition, Flow}
  alias ExAgent.Message.Part.ToolCall
  alias ExAgent.Models.Test

  defmodule Reading do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:amount, :integer)
    end

    def changeset(data, attrs) do
      data
      |> Ecto.Changeset.cast(attrs, [:amount])
      |> Ecto.Changeset.validate_required([:amount])
      |> Ecto.Changeset.validate_number(:amount, greater_than: 0)
    end
  end

  def run do
    Application.put_env(:req_llm, :load_dotenv, false)
    {:ok, _} = Application.ensure_all_started(:exagent)
    {:ok, owner} = Store.ETS.start_link(table: __MODULE__)
    counts = :atomics.new(7, signed: false)
    store = Store.scoped({Store.ETS, __MODULE__}, "coordination-recipes")

    try do
      {:ok, extracted} = ExAgent.run(extractor(counts), "Read the amount: 7")
      %Reading{amount: 7} = extracted.output
      1 = :atomics.get(counts, 1)

      {:ok, router} =
        Flow.new(
          id: "specialists",
          version: "1",
          kind: :router,
          select_version: "1",
          select: fn
            "checked" -> "checked"
            _ -> "draft"
          end,
          branches: [
            branch("draft", specialist(counts, 2, "draft")),
            branch("checked", specialist(counts, 3, "checked"))
          ]
        )

      {:ok, routed} = Flow.run(router, "checked", continuation: config(store, "route"))
      :completed = routed.status

      [%{"id" => "checked", "output" => "checked", "status" => "completed"}] =
        Enum.map(routed.output, &Map.take(&1, ["id", "output", "status"]))

      0 = :atomics.get(counts, 2)
      1 = :atomics.get(counts, 3)

      publishing =
        branch("publish", publisher(counts))
        |> Map.merge(%{
          input: fn _, outputs ->
            :atomics.add(counts, 7, 1)

            {:ok, %Reading{amount: amount}} =
              ExAgent.OutputSchema.validate(Reading, Jason.decode!(outputs["extract"]))

            {:ok, Jason.encode!(%{"amount" => amount})}
          end,
          input_version: "1"
        })

      {:ok, pipeline} =
        Composition.new(
          id: "human-reviewed",
          version: "1",
          steps: [branch("extract", json_extractor(counts)), publishing]
        )

      options = [
        continuation: config(store, "pipeline"),
        step_options: %{"publish" => [permissions: Permissions.new!(default: :ask)]}
      ]

      {:ok, paused} = Composition.run(pipeline, "Read the amount: 7", options)
      :paused = paused.status
      2 = paused.request_count
      2 = :atomics.get(counts, 1)
      1 = :atomics.get(counts, 4)
      0 = :atomics.get(counts, 5)
      1 = :atomics.get(counts, 7)

      {:ok, %{status: :pending, record: record}} = Continuation.get(store, "pipeline")
      [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

      decision = [
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "review",
        approval_id: approval_id,
        payload_hash: approval["payload_hash"],
        authorize: &authorize/3
      ]

      {:error, :unauthorized} =
        Continuation.decide(store, "pipeline", :approve, Keyword.put(decision, :actor, :guest))

      0 = :atomics.get(counts, 5)

      {:ok, %{record: approved}} =
        Continuation.decide(store, "pipeline", :approve, Keyword.put(decision, :actor, :reviewer))

      reference = %{
        version: 1,
        id: "pipeline",
        record_id: approved["record_id"],
        revision: approved["revision"],
        run_id: approved["execution"]["run_id"]
      }

      {:ok, completed} = Composition.resume(pipeline, reference, options)
      :completed = completed.status
      "published" = completed.output
      3 = completed.request_count
      2 = :atomics.get(counts, 1)
      2 = :atomics.get(counts, 4)
      1 = :atomics.get(counts, 5)
      7 = :atomics.get(counts, 6)
      1 = :atomics.get(counts, 7)

      # A current completed reference reads the result; it executes no callback.
      {:ok, again} = Composition.resume(pipeline, completed.continuation, options)
      "published" = again.output
      2 = :atomics.get(counts, 1)
      2 = :atomics.get(counts, 4)
      1 = :atomics.get(counts, 5)
      1 = :atomics.get(counts, 7)

      IO.puts("PASS typed extraction, selected specialist, human review and inert completed read")

      %{
        typed: extracted.output,
        specialist: routed.output,
        pipeline: completed.output,
        pipeline_requests: completed.request_count,
        publish_effects: 1
      }
    after
      GenServer.stop(owner)
    end
  end

  defp extractor(counts) do
    model = %Test{
      script: [
        fn _, _ ->
          :atomics.add(counts, 1, 1)

          {:tool_calls,
           [%ToolCall{tool_name: "final_result", tool_call_id: "reading", args: %{"amount" => 7}}]}
        end
      ]
    }

    ExAgent.new(model: model, output: Reading)
  end

  defp specialist(counts, index, text) do
    ExAgent.new(
      model: %Test{
        script: [
          fn _, _ ->
            :atomics.add(counts, index, 1)
            text
          end
        ]
      }
    )
  end

  # Persist JSON text and validate it at the trusted input boundary. A schema
  # struct needs an application-compiled Jason encoder to be durable JSON;
  # this standalone .exs recipe does not alter consolidated protocols.
  defp json_extractor(counts) do
    ExAgent.new(
      model: %Test{
        script: [
          fn _, _ ->
            :atomics.add(counts, 1, 1)
            Jason.encode!(%{"amount" => 7})
          end
        ]
      }
    )
  end

  defp publisher(counts) do
    tool =
      Tool.new(
        name: "publish",
        max_retries: 0,
        parameters_json_schema: %{
          "type" => "object",
          "required" => ["amount"],
          "additionalProperties" => false,
          "properties" => %{"amount" => %{"type" => "integer", "minimum" => 1}}
        },
        call: fn _, %{"amount" => amount} ->
          :atomics.add(counts, 5, 1)
          :atomics.put(counts, 6, amount)
          {:ok, "saved"}
        end
      )

    model = %Test{
      script: [
        fn messages, _ ->
          :atomics.add(counts, 4, 1)

          input =
            for %ExAgent.Message.Part.User{content: content} <- ExAgent.Message.parts(messages),
                do: content

          %{"amount" => amount} = input |> List.last() |> Jason.decode!()

          {:tool_calls,
           [
             %ToolCall{
               tool_name: "publish",
               tool_call_id: "publish-once",
               args: %{"amount" => amount}
             }
           ]}
        end,
        fn _, _ ->
          :atomics.add(counts, 4, 1)
          "published"
        end
      ]
    }

    ExAgent.new(model: model, tools: [tool])
  end

  # The application obtains this actor from authentication, never from a prompt.
  # This deterministic fixture demonstrates the callback contract only.
  defp authorize(:reviewer, :approve, _), do: {:ok, "example-reviewer"}
  defp authorize(_, _, _), do: {:error, :forbidden}
  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp branch(id, agent),
    do: %{
      id: id,
      agent: agent,
      definition: ref(id),
      policy: ref("host-policy"),
      model_ref: ref("test-index"),
      output_ref: ref(id <> "-output"),
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  defp config(store, id),
    do: %{
      store: store,
      id: id,
      policy: ref("host-policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }
end

if "--run" in System.argv(),
  do: ExAgent.Examples.CoordinationWorkflows.run(),
  else: IO.puts("Skipped: pass --run in an isolated offline VM to run the recipes.")

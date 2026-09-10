# Shared deterministic fixtures for framework_evals.exs and framework_load_probe.exs.
# Definitions are prepared once; scripted models consume actual tool returns.
# These synthetic contracts evaluate the framework, never model intelligence.
defmodule ExAgent.FrameworkScenarios do
  alias ExAgent.{
    CheckpointError,
    Coordination,
    Message,
    ModelRetry,
    Permissions,
    RunError,
    Server
  }

  alias ExAgent.{Store, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Models.Test, as: TestModel

  defmodule Reading do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:total, :integer)
      field(:count, :integer)
    end

    def changeset(value, attrs) do
      value
      |> Ecto.Changeset.cast(attrs, [:total, :count])
      |> Ecto.Changeset.validate_required([:total, :count])
      |> Ecto.Changeset.validate_number(:total, greater_than_or_equal_to: 0)
      |> Ecto.Changeset.validate_number(:count, greater_than: 0)
    end
  end

  # Fault injection wraps the existing JSON-roundtripping ETS Store. The table
  # belongs to the eval caller and is deleted after all conversation owners stop.
  defmodule FaultStore do
    @behaviour Store
    def save_agent_snapshot({table, counter}, snapshot) do
      if :atomics.add_get(counter, 1, 1) == 1,
        do: {:error, :simulated_unavailable},
        else: Store.ETS.save_agent_snapshot(table, snapshot)
    end

    def load_agent_snapshot({table, _}, id), do: Store.ETS.load_agent_snapshot(table, id)
    def list_agent_snapshots({table, _}), do: Store.ETS.list_agent_snapshots(table)
    def delete_agent_snapshot({table, _}, id), do: Store.ETS.delete_agent_snapshot(table, id)

    def save_session_snapshot({table, _}, value),
      do: Store.ETS.save_session_snapshot(table, value)

    def load_session_snapshot({table, _}, id), do: Store.ETS.load_session_snapshot(table, id)
    def delete_session_snapshot({table, _}, id), do: Store.ETS.delete_session_snapshot(table, id)
  end

  @input [3, 5, 8, 13]
  def input, do: @input
  def counter, do: :atomics.new(5, signed: false)
  defp increment(nil, _), do: :ok
  defp increment(ref, index), do: :atomics.add(ref, index, 1)

  def counts(ref) do
    [:requests, :tool_attempts, :effects, :unauthorized_effects, :estimator_calls]
    |> Enum.with_index(1)
    |> Map.new(fn {name, index} -> {name, :atomics.get(ref, index)} end)
  end

  defp scripted(items, counter) do
    %TestModel{
      script:
        Enum.map(items, fn item ->
          fn messages, _params ->
            increment(counter, 1)
            value = if is_function(item, 1), do: item.(messages), else: item

            parts =
              case value do
                {:tool_calls, calls} -> calls
                text when is_binary(text) -> [%Part.Text{content: text}]
              end

            # Every successful request reports the same known synthetic usage.
            %Response{parts: parts, usage: %Usage{input_tokens: 3, output_tokens: 2}}
          end
        end)
    }
  end

  def call(name, args \\ %{}, id \\ nil),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id || name, args: args}

  defp calls(name, args \\ %{}, id \\ nil), do: {:tool_calls, [call(name, args, id)]}

  defp returned(messages, name) do
    messages
    |> Message.parts()
    |> Enum.filter(&match?(%Part.ToolReturn{tool_name: ^name, status: :succeeded}, &1))
    |> List.last()
    |> Map.fetch!(:content)
  end

  def returns(result),
    do: result.messages |> Message.parts() |> Enum.filter(&match?(%Part.ToolReturn{}, &1))

  defp read_tool(values, counter, delay) do
    Tool.new(
      name: "read",
      takes_ctx: false,
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{"revision" => %{"type" => "integer"}},
        "required" => ["revision"],
        "additionalProperties" => false
      },
      max_retries: 1,
      call: fn %{"revision" => revision} ->
        increment(counter, 2)
        if delay > 0, do: Process.sleep(delay)

        if revision == 1,
          do: {:ok, values},
          else: {:error, %ModelRetry{message: "Read the current revision, 1"}}
      end
    )
  end

  defp forbidden_tool(counter) do
    Tool.new(
      name: "mutate",
      takes_ctx: false,
      call: fn _ ->
        increment(counter, 4)
        "unauthorized simulated mutation"
      end
    )
  end

  defp parent_policy, do: Permissions.new!(rules: [{"mutate", :deny}], default: :allow)

  # Reused by load rows and the typed-reading eval. A permissive child cannot
  # override the parent's deny; the negative authority eval attempts that call.
  def definition(kind, opts \\ []) when kind in [:simple, :tools, :delegation] do
    values = Keyword.get(opts, :values, @input)
    counter = opts[:counter]
    delay = Keyword.get(opts, :delay_ms, 0)
    retry? = Keyword.get(opts, :retry, false)

    if kind == :simple do
      %{
        agent: ExAgent.new(model: scripted(["local complete"], counter)),
        opts: [],
        expected: "local complete",
        requests: 1,
        spans: 2
      }
    else
      reads =
        if retry?,
          do: [calls("read", %{"revision" => 0}, "stale"), calls("read", %{"revision" => 1})],
          else: [calls("read", %{"revision" => 1})]

      final_read = fn messages ->
        values = returned(messages, "read")
        %{"total" => Enum.sum(values), "count" => length(values)}
      end

      {model, tools, requests, spans} =
        if kind == :tools do
          final = fn messages -> calls("final_result", final_read.(messages)) end
          {scripted(reads ++ [final], counter), [read_tool(values, counter, delay)], 2, 5}
        else
          child =
            ExAgent.new(
              name: "restricted-reader",
              model:
                scripted(
                  reads ++ [fn messages -> Jason.encode!(final_read.(messages)) end],
                  counter
                ),
              tools: [read_tool(values, counter, delay), forbidden_tool(counter)]
            )

          delegate =
            Coordination.delegation_tool(child, permissions: Permissions.new!(default: :allow))

          final = fn messages ->
            calls("final_result", messages |> returned("delegate") |> Jason.decode!())
          end

          {scripted([calls("delegate", %{"prompt" => "read revision 1"}), final], counter),
           [delegate], 4, 10}
        end

      %{
        agent: ExAgent.new(model: model, tools: tools, output: Reading),
        opts: [permissions: parent_policy()],
        expected: %Reading{total: Enum.sum(values), count: length(values)},
        requests: requests + if(retry?, do: 1, else: 0),
        spans: spans + if(retry?, do: 2, else: 0)
      }
    end
  end

  def execute(definition, tracing \\ nil) do
    ExAgent.run(
      definition.agent,
      "synthetic framework input",
      definition.opts ++ [observability: tracing]
    )
  end

  def correct?(definition, {:ok, result}) do
    result.output == definition.expected and result.status == :succeeded and
      result.request_count == definition.requests and
      result.usage.input_tokens == definition.requests * 3 and
      result.usage.output_tokens == definition.requests * 2 and
      result.usage_status == :complete and result.cost_status == :unknown
  end

  def correct?(_, _), do: false

  def ledger(result) do
    result
    |> Map.take([:status, :request_count, :tool_calls, :usage_status, :cost_status, :cost_cents])
    |> Map.put(:usage, Map.take(result.usage, [:input_tokens, :output_tokens]))
  end

  def reading_eval do
    counter = counter()
    definition = definition(:delegation, counter: counter, retry: true)
    table = :ets.new(__MODULE__, [:set, :public])
    {:ok, server} = Server.start_link(agent: definition.agent, store: {Store.ETS, table})

    try do
      estimator = fn usage ->
        increment(counter, 5)
        (usage.input_tokens + usage.output_tokens) / 100
      end

      {:ok, result} = Server.chat(server, "read", definition.opts ++ [estimate_cost: estimator])
      observed = counts(counter)
      %{persistence: persistence} = Server.health(server)

      criteria = %{
        typed_output_from_read: result.output == %Reading{total: 29, count: 4},
        one_explicit_retry: observed.tool_attempts == 2,
        no_unauthorized_effects: observed.unauthorized_effects == 0,
        inclusive_requests: result.request_count == 5 and observed.requests == 5,
        known_usage:
          result.usage.input_tokens == 15 and result.usage.output_tokens == 10 and
            result.usage_status == :complete,
        known_synthetic_cost: result.cost_status == :known and result.cost_cents == 0.25,
        checkpoint_confirmed: persistence.status == :confirmed and persistence.revision == 1,
        actual_snapshot: length(Store.ETS.list_agent_snapshots(table)) == 1
      }

      report("typed_reading", criteria, %{
        output: Map.from_struct(result.output),
        ledger: ledger(result),
        observed: observed,
        persistence: Map.take(persistence, [:status, :revision])
      })
    after
      stop(server)
      :ets.delete(table)
    end
  end

  def effect_eval do
    counter = counter()
    saves = :atomics.new(1, signed: false)
    table = :ets.new(__MODULE__, [:set, :public])
    receipt = :ets.new(__MODULE__, [:set, :public])
    id = "framework-effect-#{System.unique_integer([:positive])}"
    reader = definition(:delegation, counter: counter, retry: true)
    delegate = hd(reader.agent.tools)

    effect =
      Tool.new(
        name: "record",
        takes_ctx: false,
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"amount" => %{"type" => "integer", "minimum" => 0}},
          "required" => ["amount"]
        },
        call: fn %{"amount" => amount} ->
          increment(counter, 3)
          true = :ets.insert_new(receipt, {"operation-1", amount})
          {:ok, %{"id" => "operation-1", "amount" => amount}}
        end
      )

    model =
      scripted(
        [
          calls("delegate", %{"prompt" => "read before applying"}),
          fn messages ->
            %{"total" => total} = messages |> returned("delegate") |> Jason.decode!()
            calls("record", %{"amount" => total})
          end,
          fn _ -> raise "simulated model failure after the committed effect" end
        ],
        counter
      )

    agent = ExAgent.new(model: model, tools: [delegate, effect])
    store = {FaultStore, {table, saves}}
    {:ok, server} = Server.start_link(agent: agent, agent_id: id, store: store)

    try do
      estimator = fn usage ->
        increment(counter, 5)
        (usage.input_tokens + usage.output_tokens) / 100
      end

      {:error, %CheckpointError{revision: 1, result: {:error, %RunError{partial: partial}}}} =
        Server.chat(server, "apply once", permissions: parent_policy(), estimate_cost: estimator)

      before_retry = counts(counter)
      blocked = match?({:error, %CheckpointError{}}, Server.chat(server, "must not replay"))
      :ok = Server.checkpoint(server)
      :ok = Server.checkpoint(server)
      after_retry = counts(counter)
      history = Server.history(server)
      stop(server)

      # A trusted fresh model template is supplied explicitly: restore reloads
      # conversation/usage, not the failed model callback or external effects.
      {:ok, restored} =
        Server.start_link(agent: ExAgent.new(model: %TestModel{}), agent_id: id, store: store)

      try do
        snapshot = %{
          history_preserved: Server.history(restored) == history,
          usage_preserved: Server.usage(restored) == partial.usage,
          observed: counts(counter),
          receipt: :ets.lookup(receipt, "operation-1"),
          saves: :atomics.get(saves, 1)
        }

        criteria = %{
          one_effect_with_expected_value:
            snapshot.receipt == [{"operation-1", 29}] and snapshot.observed.effects == 1,
          no_unauthorized_effects: snapshot.observed.unauthorized_effects == 0,
          partial_effect_preserved:
            Enum.any?(returns(partial), &(&1.tool_name == "record" and &1.status == :succeeded)),
          explicit_retry_before_effect: snapshot.observed.tool_attempts == 2,
          failed_request_counted: partial.request_count == 6 and snapshot.observed.requests == 6,
          usage_known_subtotal:
            partial.usage.input_tokens == 15 and partial.usage.output_tokens == 10 and
              partial.usage_status == :partial,
          cost_honest:
            partial.cost_status == :unknown and partial.cost_cents == nil and
              snapshot.observed.estimator_calls == 17,
          dirty_blocks_replay: blocked,
          checkpoint_only_retry:
            before_retry == after_retry and after_retry == snapshot.observed and
              snapshot.saves == 2,
          restore_without_replay: snapshot.history_preserved and snapshot.usage_preserved
        }

        report("simulated_effect_recovery", criteria, %{
          ledger: ledger(partial),
          observed: snapshot.observed,
          save_attempts: snapshot.saves,
          receipt: Map.new(snapshot.receipt),
          cost_note:
            "Failed request makes aggregate cost unknown; reported token usage is a known subtotal"
        })
      after
        stop(restored)
      end
    after
      stop(server)
      :ets.delete(receipt)
      :ets.delete(table)
    end
  end

  def negative_controls do
    counter = counter()

    child =
      ExAgent.new(
        model:
          scripted(
            [
              calls("mutate"),
              fn messages ->
                messages
                |> Message.parts()
                |> Enum.find(&match?(%Part.ToolReturn{tool_name: "mutate"}, &1))
                |> Map.fetch!(:status)
                |> Atom.to_string()
              end
            ],
            counter
          ),
        tools: [forbidden_tool(counter)]
      )

    parent =
      ExAgent.new(
        model:
          scripted(
            [
              calls("delegate", %{"prompt" => "try forbidden mutation"}),
              fn messages -> returned(messages, "delegate") end
            ],
            counter
          ),
        tools: [
          Coordination.delegation_tool(child, permissions: Permissions.new!(default: :allow))
        ]
      )

    {:ok, denied} = ExAgent.run(parent, "control", permissions: parent_policy())
    denied_counts = counts(counter)
    # Positive wiring control: this same tool can actually record an effect.
    forbidden_tool(counter).call.(%{})

    invalid_counter = counter()

    invalid =
      ExAgent.new(
        model:
          scripted(
            [
              calls("read", %{"revision" => "1"}),
              calls("read", %{"revision" => "1"}, "bad-again")
            ],
            invalid_counter
          ),
        tools: [read_tool(@input, invalid_counter, 0)]
      )

    {:error, %RunError{partial: invalid_partial}} = ExAgent.run(invalid, "invalid JSON input")

    invalid_output =
      ExAgent.new(
        model: scripted([calls("final_result", %{"total" => -1, "count" => 4})], nil),
        output: Reading,
        output_retries: 0
      )

    {:error,
     %RunError{
       reason: {:unexpected_model_behavior, {:output_retries_exhausted, _}},
       partial: output_partial
     }} =
      ExAgent.run(invalid_output, "invalid typed output")

    criteria = %{
      inherited_deny:
        denied_counts.unauthorized_effects == 0 and denied_counts.requests == 4 and
          denied.output == "denied",
      effect_counter_is_live: counts(counter).unauthorized_effects == 1,
      schema_rejects_without_coercion:
        counts(invalid_counter).tool_attempts == 0 and
          invalid_partial.request_count == 2 and length(returns(invalid_partial)) == 2 and
          Enum.all?(returns(invalid_partial), &(&1.status == :validation_error)),
      ecto_rejects_invalid_output:
        output_partial.output == nil and output_partial.status == :failed
    }

    report("negative_controls", criteria, %{
      denied_requests: denied_counts.requests,
      unauthorized_effects_under_policy: denied_counts.unauthorized_effects,
      wiring_control_effects: counts(counter).unauthorized_effects,
      invalid_argument_requests: invalid_partial.request_count,
      invalid_output_requests: output_partial.request_count
    })
  end

  defp report(name, criteria, evidence),
    do: %{
      name: name,
      passed: Enum.all?(Map.values(criteria)),
      criteria: criteria,
      evidence: evidence
    }

  def provenance do
    root = Path.expand("..", __DIR__)

    (Path.wildcard(Path.join(root, "lib/**/*.ex")) ++
       Enum.map(
         [
           "mix.exs",
           "mix.lock",
           "examples/framework_scenarios.exs",
           "examples/framework_evals.exs",
           "test/support/framework_load_probe.exs"
         ],
         &Path.join(root, &1)
       ))
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path ->
      {Path.relative_to(path, root),
       Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}
    end)
  end

  def stop(pid), do: if(Process.alive?(pid), do: GenServer.stop(pid))
end

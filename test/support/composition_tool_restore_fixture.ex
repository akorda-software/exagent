defmodule ExAgent.CompositionToolRestoreFixture do
  alias ExAgent.{ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule Output do
    use Ecto.Schema
    @primary_key false
    @derive {Jason.Encoder, only: [:count]}
    embedded_schema do
      field(:count, :integer)
    end

    def changeset(value, attrs) do
      if owner = Process.get(:tool_restore_observer), do: send(owner, {:changeset, attrs})
      n = Process.get(:tool_restore_reflections, 0) + if(attrs == %{}, do: 1, else: 0)
      Process.put(:tool_restore_reflections, n)

      if attrs == %{} and Process.get(:tool_restore_fail_reflection) == n,
        do: raise("late reflection trap")

      if Process.get(:tool_restore_schema_trap), do: raise("output reflection trap")
      if Process.get(:tool_restore_args_trap) == attrs, do: raise("historical output validation")
      value |> Ecto.Changeset.cast(attrs, [:count]) |> Ecto.Changeset.validate_required([:count])
    end
  end

  defmodule HistoricalSchema do
    use ExAgent.Capability

    def before_model_request(_, state) do
      if state.run_step == 1 do
        tools =
          Enum.map(
            state.params.function_tools,
            &%{
              &1
              | parameters_json_schema: %{"type" => "object", "description" => "historical"},
                max_retries: 3
            }
          )

        %{state | params: %{state.params | function_tools: tools}}
      else
        tools =
          Enum.map(
            state.params.function_tools,
            &%{&1 | parameters_json_schema: %{"type" => "object"}, max_retries: 1}
          )

        %{state | params: %{state.params | function_tools: tools}}
      end
    end
  end

  defmodule OutputProxy do
    defstruct [:count]

    def __schema__(:fields) do
      n = Process.get(:tool_restore_proxy_reflections, 0) + 1
      Process.put(:tool_restore_proxy_reflections, n)
      if Process.get(:tool_restore_fail_reflection) == n, do: raise("schema fields trap")
      ExAgent.CompositionToolRestoreFixture.Output.__schema__(:fields)
    end

    def __schema__(key), do: ExAgent.CompositionToolRestoreFixture.Output.__schema__(key)

    def __schema__(key, value),
      do: ExAgent.CompositionToolRestoreFixture.Output.__schema__(key, value)

    def changeset(_, attrs),
      do:
        ExAgent.CompositionToolRestoreFixture.Output.changeset(
          %ExAgent.CompositionToolRestoreFixture.Output{},
          attrs
        )
  end

  defmodule Hooks do
    use ExAgent.Capability
    defstruct [:owner, :fail_after, mutate: false, fatal: [], trap_tools: false]
    def before_model_request(c, state), do: model(c, :before, state)
    def after_model_request(c, state), do: model(c, :after, state)

    defp model(c, phase, state) do
      send(c.owner, {:owned, state.continuation, state.execution_scope.pid})
      if phase == :after and state.run_step == c.fail_after, do: raise("new Model hook failure")

      send(
        c.owner,
        {:hook, phase, c.mutate,
         Map.take(state, [:tool_retries, :output_retries_used, :run_step, :tool_calls, :max_steps]),
         state.agent.output_retries}
      )

      if c.mutate do
        %{
          state
          | tool_retries: %{"fake" => 99},
            output_retries_used: 99,
            run_step: 99,
            tool_calls: 99,
            max_steps: 99,
            agent: %{state.agent | output_retries: 99}
        }
      else
        state
      end
    end

    def before_tool_execute(c, ctx, call) do
      send(c.owner, {:tool_hook, :before, ctx.tool_call_id})
      if c.trap_tools, do: raise("historical hook replay")
      call
    end

    def after_tool_execute(c, _ctx, call, result) do
      send(c.owner, {:tool_hook, :after, call.tool_call_id})
      if c.trap_tools or call.tool_call_id in (c.fatal || []), do: raise("fatal hook sentinel")
      result
    end
  end

  def output(value),
    do:
      response([
        %Message.Part.ToolCall{
          tool_name: "final_result",
          tool_call_id: "output",
          args: %{"count" => value}
        }
      ])

  defmodule Tap do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, q), do: Store.ETS.scan_records(c.table, ns, q)

    def transition(c, key, rev, command) do
      operation = command["operation"]
      step = get_in(command, ["payload", "intent", "payload", "step"])
      fault = c[:fault]
      fault = if is_function(fault, 1), do: fault.(command), else: fault

      boundary =
        if operation == "begin_effect" and is_integer(step), do: {:model, step}, else: operation

      before = Store.ETS.load_record(c.table, key)

      barrier(c, operation, :before)

      result =
        if fault == {boundary, :before},
          do: {:error, :test_ack_lost},
          else: Store.ETS.transition(c.table, key, rev, command)

      if c[:owner], do: send(c.owner, {:transition, key, rev, command, before, result})
      barrier(c, operation, :after)
      if fault == {boundary, :after}, do: {:error, :test_ack_lost}, else: result
    end

    defp barrier(%{barrier: {operation, phase, owner}}, operation, phase) do
      ref = make_ref()
      send(owner, {:barrier, self(), ref, operation, phase})

      receive do
        {^ref, :release} -> :ok
      end
    end

    defp barrier(_, _, _), do: :ok
  end

  def call(id, action \\ "success"),
    do: %Message.Part.ToolCall{tool_name: "effect", tool_call_id: id, args: %{"action" => action}}

  def response(parts),
    do: Message.new_response(parts, usage: %Message.Usage{input_tokens: 1, output_tokens: 1})

  def text, do: response([%Message.Part.Text{content: "done"}])

  def definition(opts \\ []) do
    owner = opts[:owner] || self()

    tool =
      Tool.new(
        name: "effect",
        max_retries: opts[:max_retries] || 1,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, args ->
          send(owner, {:tool, args})
          if opts[:tool_failure], do: raise("uncertain external effect")

          if opts[:trap] == true and args["action"] not in (opts[:allow_actions] || []),
            do: raise("historical tool replay")

          if opts[:tool_barrier] do
            send(owner, {:tool_barrier, self(), args})

            receive do
              :release -> :ok
            end
          end

          case args["action"] do
            "retry" ->
              {:retry, "correct it"}

            _ ->
              if opts[:usage],
                do: {:ok, opts[:value] || "value", opts[:usage]},
                else: {:ok, opts[:value] || "value"}
          end
        end
      )

    script = opts[:script] || [response([call("one")]), text()]

    script =
      Enum.with_index(script, fn response, index ->
        fn _, _ ->
          send(owner, {:model, index})
          if opts[:trap] && index < (opts[:new_index] || 99), do: raise("historical Model replay")
          if is_function(response, 2), do: response.(nil, nil), else: response
        end
      end)

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: if(opts[:new_tool], do: [tool, %{tool | name: "new_effect"}], else: [tool]),
        capabilities: opts[:capabilities] || [],
        output_type: opts[:output_type] || :text,
        usage_limits: opts[:usage_limits] || %ExAgent.UsageLimits{},
        max_steps: opts[:max_steps] || 10,
        output_retries: opts[:output_retries] || 2
      )

    step = %{
      id: "A",
      agent: agent,
      input: fn input, _ ->
        send(owner, :mapping)
        if opts[:trap], do: raise("historical mapping replay")
        {:ok, input}
      end,
      input_version: "1",
      model_codec: %{
        dump: fn m ->
          if opts[:unavailable_at] == m.index,
            do: {:error, :model_data_unavailable},
            else: {:ok, %{"index" => m.index}}
        end,
        load: fn m, data ->
          send(owner, :codec)
          {:ok, %{m | index: data["index"]}}
        end
      },
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "tool-restore", version: "1", steps: [step])
    definition
  end

  def config(table, definition, opts \\ []) do
    %{
      kind: :composition,
      composition: definition,
      store:
        Store.scoped(
          {Tap,
           %{
             table: table,
             owner: opts[:owner] || self(),
             fault: opts[:fault],
             barrier: opts[:barrier]
           }},
          "tool-restore"
        ),
      id: "tool-restore",
      definition: %{"id" => "tool-restore", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: opts[:lease_ms] || 2_000,
      max_checkpoint_bytes: Record.max_bytes()
    }
  end

  def capture(table, opts \\ []) do
    definition = definition(opts)
    config = config(table, definition, opts)
    {:ok, scope} = ExecutionScope.start_structural("root", opts[:root_options] || [])

    # Historical format 9 is seeded through CAS and checked by the record codec.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "probe"},
        config
      )

    try do
      result = ExAgent.run_composition_step(writer, definition, "A", opts[:run_options] || [])
      {:ok, record} = Store.load_record(config.store, :agent, config.id)
      {result, record, config, Writer.pending(writer).token}
    after
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end
  end

  def recover(record, config) do
    command = %{
      "operation" => "recover",
      "operation_id" => "recover-#{record["revision"]}",
      "actor_id" => "admin",
      "record_id" => record["record_id"],
      "payload" => %{}
    }

    # Await the actual UTC lease boundary; the real Store reducer, not elapsed
    # time, is the oracle that recovery is legal. No fabricated ready record.
    ref = make_ref()

    Process.send_after(
      self(),
      ref,
      max(0, record["execution"]["lease_until"] - System.system_time(:millisecond) + 1)
    )

    receive do
      ^ref -> :ok
    end

    {:ok, %{record: ready}} =
      Store.transition(config.store, :agent, config.id, record["revision"], command)

    ready
  end

  def resume(record, config, definition, opts \\ []) do
    reference = %{id: config.id, record_id: record["record_id"], revision: record["revision"]}

    ExAgent.resume_composition_step(
      definition,
      reference,
      Keyword.put(opts, :continuation, %{config | composition: definition})
    )
  end
end

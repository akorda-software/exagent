defmodule ExAgent.DelegationRuntimeFailureTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.Part.{ToolCall, ToolReturn}
  alias ExAgent.{RunError, Store, Tool}

  defmodule FailingWrapper do
    use ExAgent.Capability
    defstruct [:owner]

    def after_tool_execute(%{owner: owner}, _, _, _) do
      send(owner, {:wrapper, self()})
      raise "wrapper failed after effect"
    end
  end

  defmodule RecordingWrapper do
    use ExAgent.Capability
    defstruct [:owner]

    def after_tool_execute(%{owner: owner}, _, call, result) do
      send(owner, {:wrapped, call.tool_call_id})
      result
    end
  end

  defmodule FailingPreparation do
    use ExAgent.Capability
    defstruct []
    def before_tool_execute(_, _, _), do: raise("preparation failed")
  end

  defmodule SelectiveWrapper do
    use ExAgent.Capability
    defstruct [:owner]

    def after_tool_execute(%{owner: owner}, _, call, result) do
      send(owner, {:wrapped, call.tool_call_id})
      if call.tool_call_id == "one", do: raise("fatal wrapper"), else: result
    end
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

  defp definition(agent) do
    Composition.new(
      id: "failure",
      version: "1",
      steps: [
        %{
          id: "A",
          agent: agent,
          definition: ref("A"),
          policy: ref("policy"),
          model_ref: ref("model"),
          output_ref: ref("output"),
          model_codec: codec()
        }
      ]
    )
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "delegation-failure")
    owner = self()

    config = %{
      store: store,
      id: "run",
      policy: ref("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      on_writer: fn writer ->
        send(owner, {:writer, writer})
        :ok
      end
    }

    %{store: store, config: config}
  end

  for mode <- [:after_hook, :oversized, :invalid_usage] do
    @tag mode: mode
    test "#{mode}: confirmed effect drains and closes a failed durable root", c do
      owner = self()

      tool =
        Tool.new(
          name: "effect",
          max_retries: 0,
          takes_ctx: false,
          parameters_json_schema: %{"type" => "object"},
          call: fn _ ->
            send(owner, {:effect, self()})

            case c.mode do
              :oversized ->
                {:ok, String.duplicate("x", 65_536)}

              :invalid_usage ->
                {:ok, "done", %ExAgent.Message.Usage{input_tokens: -1, output_tokens: 1}}

              _ ->
                {:ok, "done"}
            end
          end
        )

      agent =
        ExAgent.new(
          tools: [tool],
          capabilities: if(c.mode == :after_hook, do: [%FailingWrapper{owner: owner}], else: []),
          model: %ExAgent.Models.Test{
            script: [
              {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]},
              fn _, _ ->
                send(owner, :forbidden_model)
                "unexpected"
              end
            ]
          }
        )

      {:ok, definition} = definition(agent)

      assert {:error, %RunError{partial: result, reason: reason}} =
               Composition.run(definition, "input", continuation: c.config)

      assert_receive {:effect, worker}
      refute Process.alive?(worker)
      assert_receive {:writer, writer}
      refute Process.alive?(writer)
      refute_receive :forbidden_model
      assert result.request_count == 1 and result.tool_calls == 1
      assert {:ok, record} = Store.load_record(c.store, :agent, "run")
      root = record["execution"]["progress"]["runtime"]

      assert record["execution"]["state"] == "failed",
             inspect(
               %{
                 reason: reason,
                 frontier: root["frontier"],
                 effects:
                   Enum.map(record["execution"]["effects"], fn {_, e} ->
                     {e["state"], e["outcome"]["status"]}
                   end),
                 calls:
                   Enum.map(root["tool_batches"], fn {_, b} -> {b["calls"], b["observations"]} end)
               },
               limit: 20,
               printable_limit: 300
             )

      assert root["cursor"] == "failed" and root["frontier"]["state"] == "quiescent"
      assert :ok = Record.validate(record, {"delegation-failure", :agent, "run"})
      assert Enum.all?(record["execution"]["effects"], fn {_, e} -> e["state"] == "confirmed" end)
      assert {:ok, inspected} = ExAgent.Continuation.get(c.store, "run")
      assert inspected.record["execution"]["state"] == "failed"
    end
  end

  test "ordinary runs preserve their 1 MiB payload tool slot", _c do
    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ -> {:ok, String.duplicate("x", 70_000)} end
      )

    agent =
      ExAgent.new(
        tools: [tool],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]},
            "done"
          ]
        }
      )

    assert {:ok, result} = ExAgent.run(agent, "input")

    assert Enum.any?(result.messages, fn message ->
             Enum.any?(message.parts, fn
               %ToolReturn{content: content, payload_omitted: nil} when is_binary(content) ->
                 byte_size(content) == 70_000

               _ ->
                 false
             end)
           end)
  end

  for delta <- [0, 1] do
    @tag delta: delta
    test "durable 64 KiB slot #{delta}: exact returns or marker and no wrapper replay", c do
      owner = self()

      base = %ToolReturn{
        tool_name: "effect",
        tool_call_id: "one",
        status: :succeeded,
        content: ""
      }

      content =
        String.duplicate(
          "x",
          65_536 - byte_size(ExAgent.Continuation.Outcome.encode(base)) + c.delta
        )

      assert byte_size(ExAgent.Continuation.Outcome.encode(%{base | content: content})) ==
               65_536 + c.delta

      tool =
        Tool.new(
          name: "effect",
          takes_ctx: false,
          call: fn _ ->
            send(owner, :effect)
            {:ok, content}
          end
        )

      agent =
        ExAgent.new(
          tools: [tool],
          capabilities: [%RecordingWrapper{owner: owner}],
          model: %ExAgent.Models.Test{
            script: [
              {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]},
              "done"
            ]
          }
        )

      {:ok, definition} = definition(agent)
      result = Composition.run(definition, "input", continuation: c.config)
      assert_receive :effect
      {:ok, record} = Store.load_record(c.store, :agent, "run")
      root = record["execution"]["progress"]["runtime"]
      [batch] = Map.values(root["tool_batches"])
      phase = batch["calls"]["one"]

      {:ok, [%ExAgent.Message.Request{parts: [raw]}]} =
        ExAgent.Message.from_json(phase["raw"]["result"])

      if c.delta == 0 do
        assert {:ok, %{status: :completed, output: "done"}} = result
        assert raw.content == content and raw.payload_omitted == nil
        assert_receive {:wrapped, "one"}
      else
        assert {:error, %RunError{partial: %{status: :failed}}} = result
        assert raw.content == nil
        assert raw.payload_omitted == ExAgent.Retention.marker(:tool_return, 65_537, 65_536)
        assert phase["control"] == nil and phase["state"] == "blocked"
        assert phase["raw"]["control"]["error"]["omitted"] == raw.payload_omitted
        refute_receive {:wrapped, _}
      end

      refute_receive :effect
      assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
      assert {:ok, %{record: ^record}} = ExAgent.Continuation.get(c.store, "run")
    end
  end

  test "a confirmed preparation failure closes with no tool effect or invented intent", c do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          send(owner, :forbidden_effect)
          {:ok, "done"}
        end
      )

    agent =
      ExAgent.new(
        tools: [tool],
        capabilities: [%FailingPreparation{}],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]}
          ]
        }
      )

    {:ok, definition} = definition(agent)
    assert {:error, %RunError{}} = Composition.run(definition, "input", continuation: c.config)
    refute_receive :forbidden_effect
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "failed"

    assert Enum.count(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool"
           end) == 0

    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
  end

  test "fatal wrapper drains a second admitted effect and preserves its confirmed usage", c do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: true,
        call: fn ctx, _ ->
          send(owner, {:entered, ctx.tool_call_id, self()})

          receive do
            :release -> {:ok, "done", %ExAgent.Message.Usage{input_tokens: 1, output_tokens: 2}}
          end
        end
      )

    agent =
      ExAgent.new(
        tools: [tool],
        capabilities: [%SelectiveWrapper{owner: owner}],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls,
             for(
               id <- ~w(one two),
               do: %ToolCall{tool_name: "effect", tool_call_id: id, args: %{}}
             )},
            fn _, _ ->
              send(owner, :forbidden_model)
              "unexpected"
            end
          ]
        }
      )

    {:ok, definition} = definition(agent)
    task = Task.async(fn -> Composition.run(definition, "input", continuation: c.config) end)
    assert_receive {:entered, "one", first}, 3_000
    assert_receive {:entered, "two", second}, 3_000
    send(first, :release)
    assert_receive {:wrapped, "one"}, 3_000
    assert Process.alive?(second)
    send(second, :release)
    assert {:error, %RunError{partial: result}} = Task.await(task, 20_000)
    refute Process.alive?(first) or Process.alive?(second)
    refute_receive :forbidden_model
    assert result.request_count == 1 and result.tool_calls == 2
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "failed"

    assert Enum.count(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool" and e["state"] == "confirmed"
           end) == 2

    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
    root = record["execution"]["progress"]["runtime"]
    tools = Enum.filter(root["scope"]["operations"], &match?(["tool" | _], &1["id"]))
    assert length(tools) == 2

    assert Enum.all?(
             tools,
             &(&1["usage"]["input_tokens"] == 1 and &1["usage"]["output_tokens"] == 2)
           )
  end

  test "unknown tool IO preserves a confirmed subtotal and requires explicit uncertain recovery",
       c do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          send(owner, :tool_entered)
          raise "unconfirmed external effect"
        end
      )

    agent =
      ExAgent.new(
        tools: [tool],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]},
            fn _, _ ->
              send(owner, :forbidden_model)
              "unexpected"
            end
          ]
        }
      )

    {:ok, definition} = definition(agent)
    config = %{c.config | lease_ms: 2_000}

    assert {:error, %RunError{partial: result}} =
             Composition.run(definition, "input", continuation: config)

    assert_receive :tool_entered

    assert result.request_count == 1 and result.tool_calls == 1 and
             result.usage_status == :partial

    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "claimed" and Record.unresolved?(record["execution"])
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})

    receive do
    after
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    assert {:ok, %{record: recovered}} =
             ExAgent.Continuation.recover(c.store, "run",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-tool",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    assert recovered["execution"]["state"] == "uncertain"

    assert recovered["execution"]["progress"]["active_budget"] ==
             record["execution"]["progress"]["active_budget"]

    assert {:error, %RunError{reason: :unsupported_composition_boundary}} =
             Composition.resume(
               definition,
               ExAgent.SequenceApprovalFixture.reference(recovered),
               continuation: config
             )

    refute_receive :tool_entered
    refute_receive :forbidden_model
    assert {:ok, ^recovered} = Store.load_record(c.store, :agent, "run")
  end

  test "unconfirmed Model IO remains uncertain after explicit recovery, with no callback replay",
       c do
    owner = self()

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            fn _, _ ->
              send(owner, :model_entered)
              raise "unconfirmed model request"
            end
          ]
        }
      )

    {:ok, definition} = definition(agent)
    config = %{c.config | lease_ms: 2_000}

    assert {:error, %RunError{partial: %{usage_status: :partial}}} =
             Composition.run(definition, "input", continuation: config)

    assert_receive :model_entered
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "claimed" and Record.unresolved?(record["execution"])
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})

    receive do
    after
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    assert {:ok, %{record: recovered}} =
             ExAgent.Continuation.recover(c.store, "run",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-model",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    assert recovered["execution"]["state"] == "uncertain"
    reference = ExAgent.SequenceApprovalFixture.reference(recovered)

    assert {:error, %RunError{reason: :unsupported_composition_boundary}} =
             Composition.resume(definition, reference, continuation: config)

    refute_receive :model_entered
    assert {:ok, ^recovered} = Store.load_record(c.store, :agent, "run")
  end
end

defmodule ExAgent.SequenceActiveEvidenceFixture do
  alias ExAgent.{Continuation, SequenceApprovalFixture, Store}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part.ToolCall

  defmodule EffectiveArgs do
    use ExAgent.Capability
    defstruct []

    def before_tool_execute(_, _, call),
      do: %{call | args: Map.update!(call.args, "label", &(&1 <> "-effective"))}
  end

  defmodule Arm do
    use ExAgent.Capability
    defstruct [:control, :operation, step: 1, mode: :after]

    def before_model_request(c, state) do
      if state.run_step == c.step, do: Agent.update(c.control, fn _ -> {c.operation, c.mode} end)
      state
    end
  end

  def tool_definition(effects, opts) do
    base = SequenceApprovalFixture.definition(effects, opts[:trap] || false)
    [a, _, c] = base.steps
    [b] = ExAgent.CompositionToolRestoreFixture.definition(opts).steps
    b = %{b | id: "B"}
    {:ok, definition} = Composition.new(id: base.id, version: base.version, steps: [a, b, c])
    definition
  end

  def definition(effects, fresh \\ false) do
    original = SequenceApprovalFixture.definition(effects, fresh)
    [a, b, c] = original.steps
    [batch | _] = b.agent.model.script

    script = [
      if(fresh, do: fn _, _ -> raise("historical B model") end, else: batch),
      {:tool_calls, [%ToolCall{tool_name: "final_result", tool_call_id: "b1", args: %{}}]},
      {:tool_calls,
       [%ToolCall{tool_name: "final_result", tool_call_id: "b1", args: %{"count" => 7}}]}
    ]

    b = %{
      b
      | agent: %{
          b.agent
          | output_type: ExAgent.CompositionOutputSuccessFixture.Output,
            tools:
              if(fresh,
                do:
                  Enum.map(
                    b.agent.tools,
                    &%{&1 | call: fn _, _ -> raise("historical B tool") end}
                  ),
                else: b.agent.tools
              ),
            model: %{b.agent.model | script: script}
        }
    }

    {:ok, definition} =
      Composition.new(id: original.id, version: original.version, steps: [a, b, c])

    definition
  end

  def recover(store) do
    {:ok, stored} = Store.load_record(store, :agent, "run")
    # Wait for a real lease expiry, not for ordering between concurrent events.
    wait = max(stored["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "run",
        record_id: stored["record_id"],
        revision: stored["revision"],
        operation_id: "recover-#{stored["revision"]}",
        actor: "host",
        authorize: fn actor, _, _ -> {:ok, actor} end
      )

    recovered
  end
end

defmodule ExAgent.DelegationRuntimeFixture do
  alias ExAgent.{Store, Tool}
  alias ExAgent.Continuation.Record
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part.ToolCall

  defmodule LargeOutput do
    use Ecto.Schema
    @derive Jason.Encoder
    @primary_key false
    embedded_schema do
      field(:value, :string)
    end

    def changeset(output, attrs), do: Ecto.Changeset.cast(output, attrs, [:value])
  end

  defmodule Hooks do
    use ExAgent.Capability
    defstruct [:path]

    def before_tool_execute(%{path: path}, _, call) do
      File.write!(path, "before:#{call.tool_call_id}\n", [:append])
      call
    end

    def after_tool_execute(%{path: path}, _, call, result) do
      File.write!(path, "after:#{call.tool_call_id}\n", [:append])
      result
    end
  end

  # The VM fault is immediately BEFORE the parent wrapper's durable admission.
  # Every earlier ACK is persisted; only JSON bytes cross the VM boundary.
  defmodule Journal do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      if c[:crash] == "before" and command["operation"] == "call_wrap" and
           command["payload"]["call_id"] == "delegate" do
        :erlang.halt(71)
      end

      result = Store.ETS.transition(c.table, key, revision, command)

      case result do
        {:ok, %{record: record}} -> File.write!(c.path, Jason.encode!(record))
        _ -> :ok
      end

      if c[:crash] == "wrapping" and command["operation"] == "call_wrap" and
           command["payload"]["call_id"] == "delegate" and match?({:ok, _}, result),
         do: :erlang.halt(72)

      result
    end
  end

  def reference(id), do: %{"id" => id, "version" => "1"}

  def codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, d -> {:ok, %{m | index: d["index"]}} end
    }

  defp call(name, id, args \\ %{}), do: %ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp effect(path, name, label, forbidden?) do
    Tool.new(
      name: name,
      takes_ctx: true,
      parameters_json_schema: %{"type" => "object"},
      call: fn ctx, _ ->
        if forbidden?, do: raise("confirmed tool repeated")
        suffix = if name == "ask", do: ":" <> ctx.tool_call_id, else: ""
        File.write!(path, label <> suffix <> "\n", [:append])
        {:ok, label <> " raw"}
      end
    )
  end

  def host(path, fresh? \\ false) do
    a =
      make_agent(
        [{:tool_calls, [call("effect", "a")]}, "A final"],
        [effect(path, "effect", "A", fresh?)],
        path
      )

    d =
      make_agent(
        [
          {:tool_calls, [call("effect", "d"), call("ask", "ask1"), call("ask", "ask2")]},
          "D final"
        ],
        [effect(path, "effect", "D", fresh?), effect(path, "ask", "ASK", false)],
        path
      )

    descriptor = %{
      definition: reference("D"),
      policy: reference("policy"),
      model_ref: reference("model"),
      model_codec: codec()
    }

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> raise("durable builder called") end,
        name: "delegate",
        prompt_arg: "task",
        continuation: descriptor
      )

    b =
      make_agent(
        [
          {:tool_calls,
           [call("effect", "b"), call("delegate", "delegate", %{"task" => "D input"})]},
          "B final"
        ],
        [effect(path, "effect", "B", fresh?), delegate],
        path
      )

    c =
      make_agent(
        [
          fn _, _ ->
            File.write!(path, "C\n", [:append])
            "C final"
          end
        ],
        [],
        path
      )

    steps =
      for {id, agent} <- [{"A", a}, {"B", b}, {"C", c}] do
        codec =
          if fresh? and id == "A",
            do: %{
              dump: fn _ -> raise("historical dump") end,
              load: fn _, _ -> raise("historical load") end
            },
            else: codec()

        %{
          id: id,
          agent: agent,
          definition: reference(id),
          policy: reference("policy"),
          model_ref: reference("model"),
          output_ref: reference("output"),
          model_codec: codec
        }
      end

    {:ok, definition} = Composition.new(id: "delegation-vm", version: "1", steps: steps)

    catalog = [
      %{
        definition: reference("D"),
        policy: reference("policy"),
        model_ref: reference("model"),
        load: fn _, _ ->
          {:ok, d,
           [permissions: ExAgent.Permissions.new!(default: :allow, rules: [{"ask", :ask}])],
           %{model_codec: codec()}}
        end
      }
    ]

    {definition, catalog}
  end

  defp make_agent(script, tools, path),
    do:
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: tools,
        max_payload_bytes: 16_384,
        capabilities: [%Hooks{path: path}]
      )

  def import(table, record) do
    [ns, "agent", id] = record["key"]
    key = {ns, :agent, id}
    {:ok, ^record} = Record.decode(Jason.encode!(record), key)
    {:ok, physical} = Record.key(key)
    true = :ets.insert(table, {physical, Jason.encode!(record)})
  end

  def config(store),
    do: %{
      store: store,
      id: "run",
      policy: reference("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 20_000
    }
end

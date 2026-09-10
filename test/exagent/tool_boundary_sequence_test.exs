defmodule ExAgent.ToolBoundarySequenceTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, Permissions, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Models.Test, as: TestModel

  defmodule ExecutableLiteral do
    def json_schema do
      :ets.update_counter(__MODULE__, :callbacks, 1)
      %{"type" => "object"}
    end

    def __jsv__(_, builder) do
      :ets.update_counter(__MODULE__, :callbacks, 1)
      {:nocast, builder}
    end
  end

  defmodule Rewrite do
    use ExAgent.Capability
    defstruct [:targets]

    def before_tool_execute(cap, _, call) do
      {name, args} = Map.fetch!(cap.targets, call.tool_call_id)
      %{call | tool_name: name, args: args}
    end

    def after_tool_execute(_, _, %{tool_name: "after"}, _), do: raise("after completed effect")
    def after_tool_execute(_, _, _, result), do: result
  end

  defmodule ReplaceBatch do
    use ExAgent.Capability
    defstruct [:parts]

    def after_model_request(cap, state) do
      response = %{List.last(state.messages) | parts: cap.parts}
      %{state | messages: List.replace_at(state.messages, -1, response)}
    end
  end

  test "seeded ref relocation and cached definition edits preserve original keys and inert defaults" do
    for seed <- [11_101, 11_102],
        dialect <- [
          "http://json-schema.org/draft-07/schema#",
          "https://json-schema.org/draft/2020-12/schema"
        ],
        container <- ["$defs", "default"] do
      key = Enum.at(["node/a~b", "δ/schema"], rem(seed, 2))
      pointer = "#/" <> container <> "/" <> escape(key)
      initial = reference_schema(dialect, container, key, pointer, "integer")
      tool = tool("record", initial, fn args -> {:ok, args} end)
      assert {:ok, cached} = Tool.prepare(tool)
      valid_integer = if rem(seed, 2) == 0, do: %{value: 2.0}, else: %{"value" => 2}
      assert {:ok, original} = Tool.validate_args(cached, valid_integer)
      assert original === valid_integer

      # Change only a referenced target, then return to the original definition.
      # Neither its cache nor the private default projection may retain old rules.
      changed_schema = reference_schema(dialect, container, key, pointer, "string")
      changed = %{cached | parameters_json_schema: changed_schema}
      valid_string = if rem(seed, 2) == 0, do: %{"value" => "2"}, else: %{value: "2"}
      assert {:error, [_ | _]} = Tool.validate_args(changed, valid_integer)
      assert {:ok, original} = Tool.validate_args(changed, valid_string)
      assert original === valid_string
      assert Tool.definition(changed).parameters == changed_schema
      assert {:error, [_ | _]} = Tool.validate_args(cached, valid_string)
      assert {:ok, ^valid_integer} = Tool.validate_args(cached, valid_integer)
      assert Tool.definition(cached).parameters == initial
      refute Map.has_key?(original, "omitted")
      refute Map.has_key?(original, :omitted)
    end
  end

  test "promoting cached inert literals to referenced schemas fails before any model or callable" do
    journal = start_supervised!({Agent, fn -> [] end})
    counter = :ets.new(ExecutableLiteral, [:named_table, :public])
    :ets.insert(counter, {:callbacks, 0})
    # A static, test-owned table observes callbacks even in the stream worker.
    # The existing ToolValidationTest proves JSV reaches these callback forms;
    # this control checks that this test's cross-process observer is live.
    assert ExecutableLiteral.json_schema() == %{"type" => "object"}
    assert :ets.lookup_element(counter, :callbacks, 2) == 1
    :ets.insert(counter, {:callbacks, 0})
    module = Atom.to_string(ExecutableLiteral)

    unsafe = [
      %{"x-jsv-cast" => [module]},
      %{"$ref" => "jsv:module:" <> module},
      %{"$ref" => "file:///scope-boundary-never-read.json"},
      %{"$ref" => "https://scope-boundary.invalid/schema"},
      %{"$schema" => "http://json-schema.org/draft-07/schema#", "type" => "object"}
    ]

    for seed <- [11_201, 11_202], unsafe <- permute(unsafe, seed) do
      key = if rem(seed, 2) == 0, do: "a/b~", else: "nested"
      schema = %{"type" => "object", "default" => %{key => unsafe}}

      original =
        tool("record", schema, fn args ->
          Agent.update(journal, &[:callable | &1])
          {:ok, args}
        end)

      model = %TestModel{
        script: [
          fn _, _ ->
            Agent.update(journal, &[:model | &1])
            "done"
          end
        ]
      }

      agent = ExAgent.new(model: model, tools: [original])
      assert {:ok, _} = ExAgent.run(agent, "positive inert-literal control")
      assert Agent.get(journal, & &1) == [:model]
      Agent.update(journal, fn _ -> [] end)

      referenced = Map.put(schema, "$ref", "#/default/" <> escape(key))
      cached = %{hd(agent.tools) | parameters_json_schema: referenced}
      changed = %{agent | tools: [cached]}

      for mode <- [:sync, :stream] do
        assert {:error, %RunError{reason: {:invalid_tool_schema, [_ | _]}, partial: partial}} =
                 run(changed, mode)

        assert partial.request_count == 0
        assert partial.tool_calls == 0
        assert Agent.get(journal, & &1) == []
        assert :ets.lookup_element(counter, :callbacks, 2) == 0
      end

      # The rejected edit cannot poison the still-valid reusable definition.
      assert {:ok, _} = ExAgent.run(agent, "reused inert-literal control")
      assert Agent.get(journal, & &1) == [:model]
      Agent.update(journal, fn _ -> [] end)
    end
  end

  test "seeded effective-tool batches preserve every outcome, known usage and completed effect" do
    journal = start_supervised!({Agent, fn -> [] end})

    for seed <- [11_301, 11_302, 11_303], mode <- [:sync, :stream] do
      Agent.update(journal, fn _ -> [] end)

      integer = %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "integer"}},
        "required" => ["value"]
      }

      targets = %{
        "ok" => {"record", %{"value" => 7}},
        "invalid" => {"record", %{"value" => 7, value: 8}},
        "denied" => {"protected", %{"value" => 8}},
        "encoding" => {"encoding", %{}},
        "failed" => {"failed", %{}},
        "after" => {"after", %{}}
      }

      expected = %{
        "ok" => :succeeded,
        "invalid" => :validation_error,
        "denied" => :denied,
        "encoding" => :unknown,
        "failed" => :failed,
        "after" => :succeeded
      }

      callback = fn name, value ->
        fn args ->
          Agent.update(journal, &[{:callable, name, args} | &1])
          value
        end
      end

      tools = [
        tool("dispatch", %{}, callback.("dispatch", "wrong tool")),
        tool("record", integer, callback.("record", {:ok, %{"saved" => true}, usage(2, 1)})),
        tool("protected", integer, callback.("protected", "unauthorized")),
        tool(
          "encoding",
          %{},
          callback.(
            "encoding",
            {:ok, %{nested: [Jason.Fragment.new(~S({"x":1,"\u0078":2}))]}, usage(3, 1)}
          )
        ),
        tool("failed", %{}, callback.("failed", {:error, :known_failure})),
        tool("after", %{}, callback.("after", {:ok, "saved before hook", usage(4, 2)}))
      ]

      calls = for id <- permute(Enum.sort(Map.keys(targets)), seed), do: call("dispatch", id)

      model = %TestModel{
        script: [
          fn _, _ ->
            Agent.update(journal, &[:model | &1])
            %Response{parts: calls, usage: usage(1, 1)}
          end,
          fn _, _ ->
            Agent.update(journal, &[:unexpected_replay | &1])
            "must not replay"
          end
        ]
      }

      agent = ExAgent.new(model: model, tools: tools, capabilities: [%Rewrite{targets: targets}])
      policy = Permissions.new!(rules: [{"protected", :deny}])
      assert {:error, %RunError{partial: result}} = run(agent, mode, permissions: policy)
      outcomes = returns(result)
      assert Enum.map(outcomes, & &1.tool_call_id) == Enum.map(calls, & &1.tool_call_id)
      assert Map.new(outcomes, &{&1.tool_call_id, &1.status}) == expected
      assert Enum.all?(outcomes, &(&1.tool_name == elem(Map.fetch!(targets, &1.tool_call_id), 0)))
      assert result.usage == usage(10, 5)
      assert result.request_count == 1
      assert result.tool_calls == 6
      assert_paired(result)
      events = Agent.get(journal, & &1)
      assert Enum.count(events, &(&1 == :model)) == 1
      refute :unexpected_replay in events

      assert Enum.sort(for {:callable, name, _} <- events, do: name) == [
               "after",
               "encoding",
               "failed",
               "record"
             ]

      assert {:ok, _} = result.messages |> Message.to_json() |> Message.from_json()
    end
  end

  test "effective response batch size controls atomic admission after hooks in both modes" do
    journal = start_supervised!({Agent, fn -> [] end})

    for seed <- [11_401, 11_402],
        count <- permute([0, 1, 2, 3], seed),
        mode <- [:sync, :stream] do
      Agent.update(journal, fn _ -> [] end)

      effect =
        tool("effect", %{}, fn _ ->
          Agent.update(journal, &[:effect | &1])
          "saved"
        end)

      calls = for n <- Enum.take([1, 2, 3], count), do: call("effect", "effective_#{n}")
      parts = if count == 0, do: [%Part.Text{content: "removed"}], else: calls

      model = %TestModel{
        script: [
          fn _, _ ->
            Agent.update(journal, &[:model | &1])
            {:tool_calls, [call("effect", "raw_1"), call("effect", "raw_2")]}
          end
        ]
      }

      agent =
        ExAgent.new(
          model: model,
          tools: [effect],
          max_steps: 1,
          usage_limits: %UsageLimits{tool_calls_limit: 1},
          capabilities: [%ReplaceBatch{parts: parts}]
        )

      outcome = run(agent, mode)

      result =
        case outcome do
          {:ok, result} -> result
          {:error, %RunError{partial: result}} -> result
        end

      case count do
        0 ->
          assert match?({:ok, %{output: "removed"}}, outcome)

        1 ->
          assert match?({:error, %RunError{reason: {:max_steps_exceeded, 1}}}, outcome)

        _ ->
          assert match?(
                   {:error, %RunError{reason: {:usage_limit_exceeded, :tool_calls, ^count}}},
                   outcome
                 )
      end

      admitted = if count == 1, do: 1, else: 0
      events = Agent.get(journal, & &1)
      assert Enum.count(events, &(&1 == :effect)) == admitted
      assert Enum.count(events, &(&1 == :model)) == 1
      assert result.tool_calls == admitted
      assert result.request_count == 1
      assert length(returns(result)) == count

      assert Enum.all?(
               returns(result),
               &(&1.status == if(count == 1, do: :succeeded, else: :not_executed))
             )

      assert_paired(result)
    end
  end

  defp reference_schema(dialect, container, key, pointer, type) do
    %{
      "$schema" => dialect,
      container => %{key => %{"type" => type}},
      "type" => "object",
      "properties" => %{
        "value" => %{"$ref" => pointer},
        "omitted" => %{
          "type" => "object",
          "default" => %{"$id" => 42, "$schema" => "literal-data"}
        }
      },
      "required" => ["value"],
      "additionalProperties" => false
    }
  end

  defp escape(key), do: key |> String.replace("~", "~0") |> String.replace("/", "~1")

  defp tool(name, schema, callback),
    do: Tool.new(name: name, takes_ctx: false, parameters_json_schema: schema, call: callback)

  defp call(name, id), do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: %{}}
  defp usage(input, output), do: %Usage{input_tokens: input, output_tokens: output}

  defp returns(result),
    do: for(%Part.ToolReturn{} = part <- Message.parts(result.messages), do: part)

  defp run(agent, mode, opts \\ [])
  defp run(agent, :sync, opts), do: ExAgent.run(agent, "go", opts)

  defp run(agent, :stream, opts) do
    events = ExAgent.run_stream(agent, "go", opts) |> Enum.to_list()
    terminals = Enum.filter(events, &match?({kind, _} when kind in [:result, :error], &1))
    assert length(terminals) == 1

    case hd(terminals) do
      {:result, result} -> {:ok, result}
      error -> error
    end
  end

  defp assert_paired(result) do
    calls = for %Part.ToolCall{tool_call_id: id} <- Message.parts(result.messages), do: id
    assert Enum.sort(calls) == Enum.sort(Enum.map(returns(result), & &1.tool_call_id))
  end

  defp permute(items, seed) do
    {ranked, _} =
      Enum.map_reduce(items, :rand.seed_s(:exsss, {seed, 11, 9}), fn item, state ->
        {rank, state} = :rand.uniform_s(state)
        {{rank, item}, state}
      end)

    ranked |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end
end

defmodule ExAgent.NativePreparationTest do
  use ExUnit.Case, async: true
  alias ExAgent.Message.Part

  defmodule Output do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:count, :integer, default: 7)
    end

    def changeset(data, attrs),
      do: data |> cast(attrs, [:count]) |> validate_number(:count, greater_than: 0)
  end

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:owner, :replies]
    def model_name(_), do: "native-preparation"
    def system(_), do: "custom"

    def profile(_),
      do: %ExAgent.ModelProfile{supports_json_schema_output: true, supports_tools: true}

    def request(model, messages, _settings, params) do
      send(model.owner, {:request, params, messages})
      [reply | rest] = model.replies
      parts = if is_list(reply), do: reply, else: [%Part.Text{content: reply}]
      {:ok, ExAgent.Message.new_response(parts), %{model | replies: rest}}
    end

    def request_stream(model, messages, settings, params) do
      {:ok, response, model} = request(model, messages, settings, params)
      [{:response, response, model}]
    end
  end

  defmodule Select do
    use ExAgent.Capability
    defstruct [:change]
    def before_model_request(cap, run), do: %{run | params: cap.change.(run)}
  end

  defp schema(minimum) do
    %{
      "type" => "object",
      "properties" => %{"count" => %{"type" => "integer", "minimum" => minimum}},
      "required" => ["count"]
    }
  end

  defp invalid_schema,
    do: %{"type" => "object", "properties" => %{"count" => %{"type" => "impossible"}}}

  defp select_schema(fun),
    do: %Select{
      change: fn run ->
        %{run.params | output_object: %{run.params.output_object | json_schema: fun.(run)}}
      end
    }

  defp agent(replies, capability) do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{type: "object", properties: %{}},
        call: fn _ ->
          send(owner, :effect)
          "confirmed"
        end
      )

    ExAgent.new(
      model: %Model{owner: owner, replies: replies},
      output: Output,
      output_mode: :native,
      tools: [tool],
      capabilities: [capability]
    )
  end

  defp run(agent, :sync), do: ExAgent.run(agent, "prepare")
  defp run(agent, :stream_text), do: ExAgent.run(agent, "prepare", stream_text: true)

  defp run(agent, :run_stream) do
    events = Enum.to_list(ExAgent.run_stream(agent, "prepare"))
    assert [terminal] = Enum.filter(events, &(elem(&1, 0) in [:result, :error]))
    assert List.last(events) == terminal

    case terminal do
      {:result, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  test "hook-selected invalid schema rejects before requests and sibling tool effects in all modes" do
    for mode <- [:sync, :stream_text, :run_stream] do
      replies = [
        [%Part.ToolCall{tool_name: "effect", args: %{}, tool_call_id: "effect-1"}],
        "{}",
        "{}"
      ]

      assert {:error, error} =
               run(agent(replies, select_schema(fn _ -> invalid_schema() end)), mode)

      assert {:invalid_output_schema, [_ | _]} = error.reason
      assert error.partial.request_count == 0
      assert error.partial.tool_calls == 0
      refute_receive {:request, _, _}, 0
      refute_receive :effect, 0
    end
  end

  test "hook-selected invalid schema rejects ReqLLM before host request admission too" do
    model =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: "native-preparation",
          extra: %{wire: %{protocol: "openai_chat"}},
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
        },
        api_key: "synthetic",
        base_url: "https://fixture.invalid/v1",
        tool_profile: :chat_tools_v1,
        output_profile: :chat_json_schema_v1
      )

    for mode <- [:sync, :stream_text, :run_stream] do
      definition = %{agent([], select_schema(fn _ -> invalid_schema() end)) | model: model}
      assert {:error, error} = run(definition, mode)
      assert {:invalid_output_schema, [_ | _]} = error.reason
      assert error.partial.request_count == 0
      assert error.partial.tool_calls == 0
      refute_receive :effect, 0
    end
  end

  test "malformed native object and mixed output inventory fail before custom IO" do
    changes = [
      fn run -> %{run.params | output_object: nil} end,
      fn run -> %{run.params | output_object: %{json_schema: nil}} end,
      fn run -> %{run.params | output_tools: [ExAgent.Tool.new(name: "final_result")]} end
    ]

    for mode <- [:sync, :stream_text, :run_stream], change <- changes do
      assert {:error, error} = run(agent(["{}", "{}"], %Select{change: change}), mode)
      assert error.reason == :invalid_output_configuration
      assert error.partial.request_count == 0
      assert error.partial.tool_calls == 0
      refute_receive {:request, _, _}, 0
      refute_receive :effect, 0
    end
  end

  test "valid effective schema changes on retry without stale validator and Ecto remains final" do
    for mode <- [:sync, :stream_text, :run_stream] do
      # First value passes schema but fails Ecto; the second passes Ecto but fails
      # the newly selected schema. Only the third satisfies both authorities.
      cap = select_schema(fn run -> schema(if run.run_step == 1, do: -10, else: 10) end)

      definition = %{
        agent([~s({"count":-1}), ~s({"count":2}), ~s({"count":12})], cap)
        | output_retries: 2
      }

      assert {:ok, result} = run(definition, mode)
      assert result.output == %Output{count: 12}
      assert result.request_count == 3
      assert result.tool_calls == 0

      for minimum <- [-10, 10, 10] do
        assert_receive {:request, params, _}
        assert params.output_object.json_schema == schema(minimum)
        assert params.output_tools == []
        assert Map.keys(params.output_object) |> Enum.sort() == [:json_schema, :module]
      end

      refute_receive :effect, 0
    end
  end

  test "invalid schema on a later step preserves confirmed effect but admits no further request" do
    for mode <- [:sync, :stream_text, :run_stream] do
      cap =
        select_schema(fn run -> if run.run_step == 1, do: schema(1), else: invalid_schema() end)

      replies = [
        [%Part.ToolCall{tool_name: "effect", args: %{}, tool_call_id: "effect-1"}],
        "{}",
        "{}"
      ]

      assert {:error, error} = run(agent(replies, cap), mode)
      assert {:invalid_output_schema, [_ | _]} = error.reason
      assert error.partial.request_count == 1
      assert error.partial.tool_calls == 1
      assert_receive {:request, _, _}
      assert_receive :effect
      refute_receive {:request, _, _}, 0
      refute_receive :effect, 0
    end
  end
end

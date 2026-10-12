defmodule ExAgent.FallbackModelTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, Model, ModelRequestParameters, ModelSettings, RequestError, Tool}
  alias ExAgent.Models.{Fallback, ReqLLM}

  defmodule Scripted do
    @moduledoc false
    @behaviour ExAgent.Model
    defstruct [:name, :script]

    def new(name, items) do
      {:ok, script} = Agent.start_link(fn -> items end)
      %__MODULE__{name: name, script: script}
    end

    defp next(model, settings) do
      item = Agent.get_and_update(model.script, fn [item | rest] -> {item, rest} end)
      send(Process.get(:owner, self()), {:attempt, model.name, settings && settings.timeout})
      item
    end

    @impl true
    def request(model, _messages, settings, _params) do
      case next(model, settings) do
        :ok -> {:ok, Message.new_response([%Message.Part.Text{content: model.name}]), model}
        error -> {:error, error}
      end
    end

    @impl true
    def request_stream(model, _messages, settings, _params) do
      case next(model, settings) do
        :ok ->
          response = Message.new_response([%Message.Part.Text{content: model.name}])
          [{:text_delta, model.name}, {:response, response, model}]

        {:late, error} ->
          [{:text_delta, "partial"}, {:error, error}]

        error ->
          [{:error, error}]
      end
    end

    @impl true
    def model_name(model), do: model.name
    @impl true
    def system(_), do: "scripted"
    @impl true
    def profile(model), do: %ExAgent.ModelProfile{supports_tools: model.name != "plain"}
  end

  defp status(code),
    do: %RequestError{provider: :fixture, status: code, reason: :model_request_failed}

  defp transport_error,
    do: %RequestError{provider: :fixture, reason: :model_request_failed, transport: :econnrefused}

  defp fallback(models, opts \\ []),
    do: Fallback.new(Keyword.merge([models: models, backoff_ms: 1, max_backoff_ms: 2], opts))

  defp request(model, settings \\ %ModelSettings{}, params \\ %ModelRequestParameters{}),
    do: Model.request(model, [], settings, params)

  setup do
    Process.put(:owner, self())
    :ok
  end

  test "retries transient statuses, then falls back to the next model" do
    a = Scripted.new("a", [status(429), status(503), status(500)])
    b = Scripted.new("b", [:ok])
    ref = :telemetry_test.attach_event_handlers(self(), [[:exagent, :model, :retry]])

    assert {:ok, response, %Fallback{models: [_, _]}} = request(fallback([a, b]))
    assert Message.Response.text(response) == "b"

    for name <- ~w(a a a b), do: assert_receive({:attempt, ^name, _})
    refute_receive {:attempt, _, _}, 0

    assert_receive {[:exagent, :model, :retry], ^ref, %{attempt: 1}, %{fallback: false}}
    assert_receive {[:exagent, :model, :retry], ^ref, %{attempt: 2}, %{fallback: false}}

    assert_receive {[:exagent, :model, :retry], ^ref, %{attempt: 3},
                    %{fallback: true, status: 500}}
  end

  test "non-transient errors, partial responses and transport failures are not retried by default" do
    for error <- [
          status(400),
          status(401),
          %{status(503) | partial_response: Message.new_response([])},
          transport_error(),
          {:unsupported, :tools}
        ] do
      a = Scripted.new("a", [error])
      b = Scripted.new("b", [:ok])
      assert {:error, ^error} = request(fallback([a, b]))
      assert_receive {:attempt, "a", _}
      refute_receive {:attempt, _, _}, 0
    end

    a = Scripted.new("a", [transport_error()])
    b = Scripted.new("b", [:ok])
    assert {:ok, _, _} = request(fallback([a, b], retry_transport: true, max_retries: 0))

    # Without a transport failure, a status-less error (e.g. a decode or
    # pre-IO failure) is never retried, even with retry_transport.
    opaque = %RequestError{provider: :fixture, reason: :model_request_failed}
    a = Scripted.new("a", [opaque])
    b = Scripted.new("b", [:ok])
    assert {:error, ^opaque} = request(fallback([a, b], retry_transport: true))
  end

  test "the run deadline bounds every attempt and stops retries that would outlive it" do
    a = Scripted.new("a", [status(503), status(503)])
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:error, %RequestError{status: 503}} =
             request(
               fallback([a], backoff_ms: 5_000, max_backoff_ms: 5_000),
               %ModelSettings{timeout: 30_000},
               %ModelRequestParameters{deadline: deadline}
             )

    assert_receive {:attempt, "a", timeout} when timeout <= 1_000
    refute_receive {:attempt, _, _}, 0
  end

  test "without a deadline every attempt keeps its receive timeout" do
    a = Scripted.new("a", [status(503), :ok])
    assert {:ok, _, _} = request(fallback([a]), %ModelSettings{timeout: 30_000})
    assert_receive {:attempt, "a", 30_000}
    assert_receive {:attempt, "a", 30_000}
  end

  test "streams retry only before the first event" do
    a = Scripted.new("a", [status(529)])
    b = Scripted.new("b", [:ok])
    model = fallback([a, b], max_retries: 0)

    events = Model.request_stream(model, [], %ModelSettings{}, %ModelRequestParameters{})

    assert [{:text_delta, "b"}, {:response, _, %Fallback{models: [^a, %Scripted{name: "b"}]}}] =
             Enum.to_list(events)

    late = Scripted.new("a", [{:late, status(503)}])
    events = Model.request_stream(fallback([late, b]), [], nil, %ModelRequestParameters{})
    assert [{:text_delta, "partial"}, {:error, %RequestError{status: 503}}] = Enum.to_list(events)
  end

  test "profile, binding and options are conservative" do
    tools = Scripted.new("a", [])
    plain = Scripted.new("plain", [])
    assert %{supports_tools: false} = Model.profile(fallback([tools, plain]))
    assert %{supports_tools: true} = Model.profile(fallback([tools, tools]))

    assert {:ok, %{"adapter" => "exagent.fallback", "models" => [nil, nil]}} =
             Model.continuation_binding(fallback([tools, tools]))

    # Strict accounting rejects :normalized, so it must not hide behind :unknown.
    normalized = ReqLLM.new(model: spec("model-a"), tool_profile: :chat_tools_v1)
    assert %{accounting_quality: :normalized} = Model.profile(fallback([normalized, tools]))
    assert %{accounting_quality: :unknown} = Model.profile(fallback([tools, tools]))

    for opts <- [
          [models: []],
          [models: [tools], max_retries: -1],
          [models: [tools], retry_statuses: [1]]
        ] do
      assert_raise ArgumentError, fn -> Fallback.new(opts) end
    end
  end

  # --- end to end over ReqLLM ---------------------------------------------

  defp spec(id) do
    %{
      provider: :openai,
      id: id,
      extra: %{wire: %{protocol: "openai_chat"}},
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
    }
  end

  defp chat(id, message, finish) do
    %{
      "id" => "reply",
      "model" => id,
      "choices" => [%{"index" => 0, "message" => message, "finish_reason" => finish}]
    }
  end

  # One fixture callback per test owner, routed by the requested model.
  defp transport(replies) do
    owner = self()
    {:ok, queues} = Agent.start_link(fn -> replies end)

    ExAgent.Test.ReqTransport.bind(fn request ->
      body = Jason.decode!(IO.iodata_to_binary(request.body))
      id = body["model"]
      send(owner, {:http, id, body})

      item =
        Agent.get_and_update(queues, fn queues ->
          [item | rest] = Map.fetch!(queues, id)
          {item, Map.put(queues, id, rest)}
        end)

      case item do
        {:transport, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, reply} ->
          {request,
           Req.Response.new(
             status: status,
             headers: [{"content-type", "application/json"}],
             body: Jason.encode!(reply)
           )}
      end
    end)
  end

  defp adapter(id, transport, opts) do
    ReqLLM.new(
      Keyword.merge(
        [
          model: spec(id),
          tool_profile: :chat_tools_v1,
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          http_options: [adapter: transport]
        ],
        opts
      )
    )
  end

  defp lookup do
    Tool.new(
      name: "lookup",
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{"q" => %{"type" => "string"}},
        "required" => ["q"],
        "additionalProperties" => false
      },
      call: fn _ctx, %{"q" => q} -> "result for #{q}" end
    )
  end

  defp call_reply(id) do
    chat(
      id,
      %{
        "role" => "assistant",
        "content" => "checking",
        "tool_calls" => [
          %{
            "id" => "call-1",
            "type" => "function",
            "function" => %{
              "name" => "lookup",
              "arguments" => Jason.encode!(%{"arguments" => %{"q" => "x"}})
            }
          }
        ]
      },
      "tool_calls"
    )
  end

  defp run_switch(opts) do
    transport =
      transport(%{
        "model-a" => [{200, call_reply("model-a")}, {503, %{"error" => "busy"}}],
        "model-b" => [
          {200, chat("model-b", %{"role" => "assistant", "content" => "done"}, "stop")}
        ]
      })

    primary = adapter("model-a", transport, opts)
    backup = adapter("model-b", transport, opts)

    agent =
      ExAgent.new(
        model: fallback([primary, backup], max_retries: 0),
        tools: [lookup()]
      )

    ExAgent.run(agent, "go")
  end

  test "a portable history lets the backup continue the primary's conversation" do
    assert {:ok, %{output: "done", request_count: 2} = result} =
             run_switch(foreign_history: :portable)

    assert_receive {:http, "model-a", _}
    assert_receive {:http, "model-a", _}
    assert_receive {:http, "model-b", body}

    assert [_, _, %{"role" => "assistant", "content" => "checking", "tool_calls" => [call]}, tool] =
             body["messages"]

    assert call["function"]["name"] == "lookup"
    assert tool["role"] == "tool" and tool["tool_call_id"] == "call-1"
    responses = Enum.filter(result.messages, &is_struct(&1, Message.Response))
    assert Enum.map(responses, & &1.model_name) == ["model-a", "model-b"]
    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
  end

  test "ReqLLM connection failures are marked as transport errors and retried only on opt-in" do
    done = {200, chat("model-b", %{"role" => "assistant", "content" => "done"}, "stop")}
    transport = transport(%{"model-a" => [{:transport, :econnrefused}], "model-b" => [done]})
    models = [adapter("model-a", transport, []), adapter("model-b", transport, [])]

    assert {:ok, %{output: "done"}} =
             ExAgent.run(
               ExAgent.new(model: fallback(models, retry_transport: true, max_retries: 0)),
               "go"
             )

    transport = transport(%{"model-a" => [{:transport, :econnrefused}], "model-b" => [done]})
    models = [adapter("model-a", transport, []), adapter("model-b", transport, [])]

    assert {:error, %ExAgent.RunError{reason: {:model_request_failed, error}}} =
             ExAgent.run(ExAgent.new(model: fallback(models)), "go")

    assert %RequestError{status: nil, reason: :model_request_failed, transport: :econnrefused} =
             error
  end

  test "a persisted history resumes when any model of the chain accepts it" do
    transport = transport(%{})
    primary = adapter("model-a", transport, [])
    backup = adapter("model-b", transport, [])

    history = [
      Message.new_request([%Message.Part.User{content: "go"}]),
      %{
        Message.new_response([%Message.Part.Text{content: "hi"}])
        | model_name: "model-b",
          continuation: %{
            "provider" => "openai",
            "model" => "model-b",
            "endpoint" => "https://fixture.invalid/v1"
          }
      }
    ]

    params = %ModelRequestParameters{}
    assert {:error, _} = Model.validate_resume(primary, history, nil, params)
    expected = Model.validate_resume(backup, history, nil, params)
    assert Model.validate_resume(fallback([primary, backup]), history, nil, params) == expected
    assert Model.validate_resume(fallback([primary, primary]), history, nil, params) != :ok
  end

  test "without a portable history the backup rejects the primary's response before IO" do
    assert {:error, %ExAgent.RunError{reason: {:model_request_failed, error}}} = run_switch([])
    assert error.reason == :continuation_target_mismatch
    refute_receive {:http, "model-b", _}, 50
  end
end

defmodule ExAgent.ReqLLMStreamTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Model, ModelRequestParameters, ModelSettings, Tool}
  alias ExAgent.Models.ReqLLM, as: Adapter

  defmodule AdmissionHook do
    use ExAgent.Capability
    defstruct [:rewrite]

    def before_tool_execute(%{rewrite: rewrite}, ctx, call) do
      send(ctx.deps.owner, {:admission_hook, call.args})

      case rewrite do
        :bad -> %{call | args: %{"value" => "bad"}}
        :id -> %{call | tool_call_id: "changed"}
        _ -> %{call | args: %{"value" => 9}}
      end
    end
  end

  defmodule EmptyOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
    end

    def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [])
  end

  setup_all do
    # Complete a real public interaction before short deadline probes; cold
    # provider/schema loading belongs to startup, not their scheduling barriers.
    {url, peer} = scripted([reply([], "stop", "warm")])
    assert [{:text_delta, "warm"}, {:response, _, _}] = stream(model(url)) |> Enum.to_list()
    assert_receive {:script_request, ^peer, 0, _}, 5000
    :ok
  end

  defmodule TypedOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:value, :string)

      embeds_one :child, Child, primary_key: false do
        field(:enabled, :boolean)
      end
    end

    def changeset(data, attrs) do
      data
      |> cast(attrs, [:value])
      |> cast_embed(:child, with: &cast(&1, &2, [:enabled]))
      |> validate_change(:value, fn :value, value ->
        if value == "bad", do: [value: "invalid"], else: []
      end)
    end
  end

  defp tool do
    owner = self()

    Tool.new(
      name: "effect",
      parameters_json_schema: %{"type" => "object"},
      call: fn ctx, args ->
        send(owner, {:effect, ctx.tool_call_id, args})
        %{"result" => args}
      end
    )
  end

  defp call(args, name \\ "effect") do
    %{
      "id" => "call-stream",
      "type" => "function",
      "function" => %{"name" => name, "arguments" => args}
    }
  end

  defp reply(calls, finish \\ "tool_calls", text \\ "") do
    %{calls: calls, finish: finish, text: text}
  end

  defp scripted(replies) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        Enum.with_index(replies, fn reply, index ->
          {:ok, socket} = :gen_tcp.accept(listener, 10_000)
          payload = socket |> read_request("") |> Jason.decode!()
          send(owner, {:script_request, self(), index, payload})

          {type, bytes} =
            if payload["stream"] do
              calls =
                Enum.with_index(reply.calls, fn call, index ->
                  args = call["function"]["arguments"]

                  initial =
                    call
                    |> Map.put("index", index)
                    |> update_in(["function"], &Map.delete(&1, "arguments"))

                  {initial, fragments} =
                    case Map.get(reply, :layout, :name) do
                      :name ->
                        {initial, String.codepoints(args)}

                      :empty ->
                        {put_in(initial, ["function", "arguments"], ""), String.codepoints(args)}

                      :prefix ->
                        {put_in(initial, ["function", "arguments"], "{"),
                         String.codepoints(String.slice(args, 1..-1//1))}

                      :full ->
                        {put_in(initial, ["function", "arguments"], args), []}

                      {:suffix, suffix} ->
                        {put_in(initial, ["function", "arguments"], args), [suffix]}

                      :missing ->
                        {initial, []}
                    end

                  [
                    frame(%{"tool_calls" => [initial]})
                    | Enum.map(fragments, fn part ->
                        frame(%{
                          "tool_calls" => [
                            %{"index" => index, "function" => %{"arguments" => part}}
                          ]
                        })
                      end)
                  ]
                end)

              calls =
                if Map.get(reply, :interleaved, false) and calls != [] do
                  for offset <- 0..(Enum.max(Enum.map(calls, &length/1)) - 1),
                      call <- Enum.reverse(calls),
                      do: Enum.at(call, offset, "")
                else
                  List.flatten(calls)
                end

              {"text/event-stream",
               frame(%{"content" => reply.text}) <>
                 Enum.join(calls) <> if(reply.finish, do: accounting_terminal(reply), else: "")}
            else
              {"application/json",
               Jason.encode!(
                 maybe_usage(
                   %{
                     "id" => "gate",
                     "model" => "stream-gate",
                     "choices" => [
                       %{
                         "index" => 0,
                         "message" => %{
                           "role" => "assistant",
                           "content" => reply.text,
                           "tool_calls" => reply.calls
                         },
                         "finish_reason" => reply.finish
                       }
                     ]
                   },
                   reply
                 )
               )}
            end

          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
              bytes
          )

          :gen_tcp.close(socket)
        end)

        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    {"http://127.0.0.1:#{port}/v1", pid}
  end

  # Predeclared finite profile: 64KiB external_size/chunk, 1MiB/4096 chunks,
  # one bridge delta, cleanup within 2s, fixture at most 2MiB, concurrency 1/8.
  defp model(url, opts \\ []) do
    Adapter.new(
      Keyword.merge(
        [
          model: %{
            provider: :openai,
            id: "stream-gate",
            extra: %{wire: %{protocol: "openai_chat"}},
            capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
          },
          tool_profile: :chat_tools_v1,
          api_key: "synthetic",
          base_url: url,
          total_timeout: 8000,
          http_options: [receive_timeout: 5000]
        ],
        opts
      )
    )
  end

  defp stream(model, params \\ %ModelRequestParameters{}) do
    Model.request_stream(
      model,
      [Message.new_request([%Message.Part.User{content: "synthetic"}])],
      %ModelSettings{},
      params
    )
  end

  defp frame(delta, finish \\ nil) do
    "data: " <>
      Jason.encode!(%{
        "id" => "gate",
        "model" => "stream-gate",
        "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => finish}]
      }) <> "\n\n"
  end

  defp terminal(reason \\ "stop"), do: frame(%{}, reason) <> "data: [DONE]\n\n"

  defp maybe_usage(body, reply) do
    if Map.has_key?(reply, :usage), do: Map.put(body, "usage", reply.usage), else: body
  end

  defp accounting_terminal(reply) do
    if Map.has_key?(reply, :usage) do
      frame(%{}, reply.finish) <>
        "data: " <>
        Jason.encode!(%{"choices" => [], "usage" => reply.usage}) <>
        "\n\ndata: [DONE]\n\n"
    else
      terminal(reply.finish)
    end
  end

  test "R1.5 normalized accounting survives tool and second turn across buffered and stream surfaces" do
    for surface <- [:run, :stream_text, :run_stream],
        usage <- [
          :missing,
          nil,
          %{},
          %{"prompt_tokens" => 7},
          %{"completion_tokens" => 2},
          %{"prompt_tokens" => 0, "completion_tokens" => 0, "total_tokens" => 0},
          %{"prompt_tokens" => 7, "completion_tokens" => 2, "total_tokens" => 9}
        ] do
      replies = [reply([call(~s({"arguments":{}}))]), reply([], "stop", "done")]

      replies =
        if usage == :missing, do: replies, else: Enum.map(replies, &Map.put(&1, :usage, usage))

      {url, peer} = scripted(replies)

      agent =
        ExAgent.new(
          model: model(url),
          tools: [tool()],
          usage_limits: %ExAgent.UsageLimits{request_limit: 2}
        )

      result =
        case surface do
          :run -> ExAgent.run(agent, "go")
          :stream_text -> ExAgent.run(agent, "go", stream_text: true)
          :run_stream -> agent |> ExAgent.run_stream("go") |> Enum.to_list() |> List.last()
        end

      result =
        case result do
          {:ok, result} -> result
          {:result, result} -> result
        end

      assert result.output == "done"
      assert result.request_count == 2
      assert result.tool_calls == 1
      assert result.usage.accounting["quality"] == "normalized"
      assert result.usage.accounting["provider_presence"] == "unknown"
      assert result.usage.accounting["version"] == 1

      if surface != :run and usage in [:missing, nil] do
        assert result.usage_status == :partial
        assert {result.usage.input_tokens, result.usage.output_tokens} == {nil, nil}
        assert result.usage.accounting["availability"]["input"] == "unavailable"
      else
        assert result.usage_status == :complete, inspect({surface, usage, result.usage})
      end

      if usage == %{"prompt_tokens" => 7, "completion_tokens" => 2, "total_tokens" => 9} do
        assert {result.usage.input_tokens, result.usage.output_tokens} == {14, 4}
      end

      assert_receive {:effect, "call-stream", %{}}
      refute_receive {:effect, _, _}, 0
      assert_receive {:script_request, ^peer, 0, _}
      assert_receive {:script_request, ^peer, 1, _}
      refute_receive {:script_request, ^peer, _, _}, 0
    end
  end

  test "explicit OpenRouter streaming retains routing, mandatory envelope and tool history" do
    {url, peer} =
      scripted([
        reply([call(Jason.encode!(%{"arguments" => %{"value" => 7}}))]),
        reply([], "stop", "done")
      ])

    routed =
      model(url,
        model: %{
          provider: :openrouter,
          id: "stream-gate",
          extra: %{wire: %{protocol: "openai_chat"}},
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
        },
        tool_profile: :openrouter_chat_tools_v1,
        provider_options: [
          openrouter_provider: %{only: ["io-net"], order: ["io-net"], allow_fallbacks: false}
        ]
      )

    assert {:ok, result} =
             ExAgent.run(ExAgent.new(model: routed, tools: [tool()]), "go", stream_text: true)

    assert result.output == "done" and result.request_count == 2
    assert_receive {:effect, _, %{"value" => 7}}, 5000
    refute_receive {:effect, _, _}, 0

    for index <- 0..1 do
      assert_receive {:script_request, ^peer, ^index, body}, 5000

      assert body["provider"] == %{
               "only" => ["io-net"],
               "order" => ["io-net"],
               "allow_fallbacks" => false
             }

      assert body["stream"] == true
      assert get_in(hd(body["tools"]), ["function", "parameters", "required"]) == ["arguments"]
    end

    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
  end

  test "routed stream invalid envelopes and incomplete terminals cannot authorize effects" do
    for {args, finish} <- [
          {"[]", "tool_calls"},
          {"{\"arguments\":[]}", "tool_calls"},
          {"{\"arguments\":{}}", "length"}
        ] do
      {url, peer} = scripted([reply([call(args)], finish)])

      m =
        model(url,
          tool_profile: :openrouter_chat_tools_v1,
          model: %{
            provider: :openrouter,
            id: "stream-gate",
            extra: %{wire: %{protocol: "openai_chat"}},
            capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
          },
          provider_options: [openrouter_provider: %{only: ["decart"]}]
        )

      assert [{:error, %ExAgent.RunError{}}] =
               ExAgent.run_stream(ExAgent.new(model: m, tools: [tool()]), "go") |> Enum.to_list()

      assert_receive {:script_request, ^peer, 0, body}
      assert body["provider"] == %{"only" => ["decart"]}
      refute_receive {:effect, _, _}, 0
    end
  end

  test "routed stream owner death closes its actual HTTP socket" do
    {url, peer} = peer()

    m =
      model(url,
        tool_profile: :openrouter_chat_tools_v1,
        model: %{
          provider: :openrouter,
          id: "stream-gate",
          extra: %{wire: %{protocol: "openai_chat"}},
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
        },
        provider_options: [openrouter_provider: %{only: ["decart"]}]
      )

    owner = spawn(fn -> Enum.to_list(stream(m)) end)
    ref = Process.monitor(owner)
    assert_receive {:request, ^peer, _}, 5000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 2000
    assert {:error, :closed} = command(peer, :closed)
  end

  test "R1.5 strict stream metric requirement rejects zero and positive fixtures before transport" do
    for tokens <- [0, 7], surface <- [:stream_text, :run_stream] do
      reply =
        Map.put(reply([], "stop", "done"), :usage, %{
          "prompt_tokens" => tokens,
          "completion_tokens" => tokens,
          "total_tokens" => tokens * 2
        })

      {url, peer} = scripted([reply])

      agent =
        ExAgent.new(model: model(url), usage_limits: %ExAgent.UsageLimits{input_tokens_limit: 10})

      outcome =
        case surface do
          :stream_text -> ExAgent.run(agent, "go", stream_text: true)
          :run_stream -> agent |> ExAgent.run_stream("go") |> Enum.to_list() |> List.last()
        end

      assert {:error,
              %ExAgent.RunError{
                reason: {:accounting_unavailable, "input", :normalized_only},
                partial: partial
              }} = outcome

      assert partial.request_count == 0
      refute_receive {:script_request, ^peer, _, _}, 0
    end
  end

  defp peer do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        case :gen_tcp.accept(listener, 10_000) do
          {:ok, socket} ->
            :gen_tcp.close(listener)
            payload = read_request(socket, "")
            send(owner, {:request, self(), Jason.decode!(payload)})

            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n"
            )

            serve(socket)

          {:error, :closed} ->
            :ok
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    {"http://127.0.0.1:#{port}/v1", pid}
  end

  defp serve(socket) do
    receive do
      {from, ref, {:send, bytes}} ->
        send(from, {ref, :gen_tcp.send(socket, bytes)})
        serve(socket)

      {from, ref, :finish} ->
        :gen_tcp.close(socket)
        send(from, {ref, :ok})

      {from, ref, :closed} ->
        send(from, {ref, :gen_tcp.recv(socket, 0, 2000)})
        :gen_tcp.close(socket)
    after
      10_000 -> :gen_tcp.close(socket)
    end
  end

  defp command(peer, command) do
    ref = make_ref()
    send(peer, {self(), ref, command})
    receive do: ({^ref, result} -> result), after: (3000 -> flunk("peer command timed out"))
  end

  defp read_request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(length) - byte_size(body)

        if missing > 0 do
          {:ok, rest} = :gen_tcp.recv(socket, missing, 5000)
          body <> rest
        else
          body
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, bytes <> more)
    end
  end

  test "vertical public Model stream is lazy, single request, provisional deltas and canonical terminal" do
    {url, peer} = peer()
    source = stream(model(url))
    refute_receive {:request, _, _}, 50
    task = Task.async(fn -> Enum.to_list(source) end)
    assert_receive {:request, ^peer, payload}, 2000
    assert payload["stream"] == true
    assert payload["max_tokens"] == 4096

    assert :ok =
             command(
               peer,
               {:send,
                frame(%{"content" => "hello "}) <> frame(%{"content" => "world"}) <> terminal()}
             )

    assert :ok = command(peer, :finish)

    assert [{:text_delta, "hello "}, {:text_delta, "world"}, {:response, response, _}] =
             Task.await(task)

    assert Message.Response.text(response) == "hello world"
    assert response.finish_reason == :stop
    assert response.continuation["version"] == 2
    assert response.usage.accounting["quality"] == "normalized"
    assert response.usage.accounting["provider_presence"] == "unknown"
    refute_receive {:request, _, _}, 0
  end

  test "tool-call argument fragments stream as previews only when requested" do
    # The wire carries the mandatory envelope; previews expose it verbatim.
    args = ~s({"arguments":{"value":"Las ratas chillan"}})

    for opt_in <- [true, false] do
      {url, _peer} = scripted([reply([call(args)])])
      params = %ModelRequestParameters{function_tools: [tool()], tool_call_deltas: opt_in}
      events = stream(model(url), params) |> Enum.to_list()
      previews = for {:tool_call_delta, delta} <- events, do: delta

      if opt_in do
        assert [%{index: 0, name: "effect", fragment: ""} | fragments] = previews
        assert Enum.map_join(fragments, & &1.fragment) == args
        assert Enum.all?(fragments, &(&1.name == nil and &1.index == 0))
      else
        assert previews == []
      end

      assert {:response, response, _} = List.last(events)

      assert [
               %Message.Part.ToolCall{
                 tool_name: "effect",
                 args: %{"value" => "Las ratas chillan"}
               }
             ] =
               response.parts
    end
  end

  test "halt and exception after a delta close real transport" do
    for mode <- [:halt, :raise] do
      {url, peer} = peer()

      task =
        Task.async(fn ->
          if mode == :halt do
            Enum.take(stream(model(url)), 1)
          else
            assert_raise RuntimeError, "consumer", fn ->
              Enum.each(stream(model(url)), fn _ -> raise "consumer" end)
            end
          end
        end)

      # Initial cold-start diagnostic measured 1831ms before first HTTP request;
      # readiness is distinct from the unchanged 2s cleanup oracle.
      assert_receive {:request, ^peer, _}, 5000

      assert :ok = command(peer, {:send, frame(%{"content" => "provisional"})})
      Task.await(task)
      assert {:error, :closed} = command(peer, :closed)
    end
  end

  test "owner death while HTTP is incomplete closes transport and owned processes" do
    {url, peer} = peer()
    owner = spawn(fn -> Enum.to_list(stream(model(url))) end)
    monitor = Process.monitor(owner)
    assert_receive {:request, ^peer, _}, 2000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 2000
    assert {:error, :closed} = command(peer, :closed)
  end

  test "owner killed before public handle registration closes stock transport" do
    parent = self()
    id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        id,
        [:req_llm, :request, :start],
        fn _, _, _metadata, _ ->
          send(parent, {:before_registration, self()})
          receive do: (:release -> :ok)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)
    {url, peer} = peer()
    owner = spawn(fn -> Enum.to_list(stream(model(url))) end)
    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:before_registration, producer}, 5000
    producer_monitor = Process.monitor(producer)
    assert_receive {:request, ^peer, _}, 2000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^producer_monitor, :process, ^producer, :shutdown}, 2000
    assert {:error, :closed} = command(peer, :closed)
  end

  test "oversized public decoded chunk is rejected before forwarding" do
    {url, peer} = peer()
    task = Task.async(fn -> Enum.to_list(stream(model(url))) end)
    assert_receive {:request, ^peer, _}, 5000
    assert :ok = command(peer, {:send, frame(%{"content" => String.duplicate("x", 256 * 1024)})})

    assert [{:error, %ExAgent.RequestError{reason: {:stream_limit, :chunk_bytes}}}] =
             Task.await(task)

    assert {:error, :closed} = command(peer, :closed)
  end

  for layout <- [:name, :empty, :prefix, :full] do
    @tag layout: layout
    test "final admission #{layout}: public Model preserves final logical arguments and diagnostics",
         %{layout: layout} do
      {url, peer} =
        scripted([Map.put(reply([call(~s({"arguments":{"value":7}}))]), :layout, layout)])

      params = %ModelRequestParameters{function_tools: [tool()]}
      assert [{:response, response, _}] = stream(model(url), params) |> Enum.to_list()

      assert [
               %Message.Part.ToolCall{
                 tool_call_id: "call-stream",
                 args: %{"value" => 7},
                 metadata: metadata
               }
             ] = response.parts

      assert metadata["arguments_codec"] == "exagent.arguments/1"

      if layout in [:empty, :prefix] do
        assert metadata["invalid_arguments"] == true
        assert metadata["unparseable_arguments"] == true
        assert metadata["raw_arguments"] == if(layout == :empty, do: "", else: "{")
      end

      assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
      refute_receive {:script_request, ^peer, _, _}, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  test "public run_stream and stream_text share buffered tool effects, IDs and once-wrapped history" do
    for mode <- [:buffered, :stream_text, :run_stream],
        layout <- [:name, :empty, :prefix, :full] do
      {url, peer} =
        scripted([
          Map.put(reply([call("{\"arguments\":{\"value\":7}}")]), :layout, layout),
          reply([], "stop", "done")
        ])

      agent = ExAgent.new(model: model(url), tools: [tool()])

      result =
        case mode do
          :run_stream ->
            source = ExAgent.run_stream(agent, "go")
            refute_receive {:script_request, ^peer, _, _}, 20
            events = Enum.to_list(source)
            assert {:delta, "done"} in events
            assert [{:result, result}] = Enum.filter(events, &match?({:result, _}, &1))
            result

          _ ->
            assert {:ok, result} = ExAgent.run(agent, "go", stream_text: mode == :stream_text)
            result
        end

      assert result.output == "done"
      assert result.request_count == 2
      assert_receive {:effect, "call-stream", %{"value" => 7}}
      refute_receive {:effect, _, _}, 0
      assert_receive {:script_request, ^peer, 0, first}
      assert [%{"function" => definition}] = first["tools"]
      assert definition["parameters"]["required"] == ["arguments"]
      assert_receive {:script_request, ^peer, 1, second}
      assistant = Enum.find(second["messages"], &(&1["role"] == "assistant"))

      assert [%{"id" => "call-stream", "function" => %{"arguments" => args}}] =
               assistant["tool_calls"]

      assert Jason.decode!(args) == %{"arguments" => %{"value" => 7}}

      assert Enum.any?(
               second["messages"],
               &(&1["role"] == "tool" and &1["tool_call_id"] == "call-stream")
             )

      response =
        Enum.find(result.messages, &match?(%Message.Response{finish_reason: :tool_calls}, &1))

      assert response.continuation["version"] == 2
      assert response.continuation["arguments_codec"] == "exagent.arguments/1"
      assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}

      assert [%Message.Part.ToolCall{args: %{"value" => 7}}] =
               Message.Response.tool_calls(response)

      returns =
        for %Message.Request{parts: parts} <- result.messages,
            %Message.Part.ToolReturn{} = part <- parts,
            do: part

      assert [
               %Message.Part.ToolReturn{
                 tool_call_id: "call-stream",
                 content: %{"result" => %{"value" => 7}}
               }
             ] = returns

      refute_receive {:script_request, ^peer, _, _}, 0
    end
  end

  test "invalid fragmented envelopes and complete JSON with incomplete terminals cause zero effects" do
    invalid = [
      "[]",
      "[{}]",
      "null",
      "\"text\"",
      "1",
      "true",
      "false",
      "{}",
      "{!}",
      "{\"arguments\":{\"value\":7,}}",
      "{\"arguments\":{}",
      "{\"arguments\":[]}",
      "{\"other\":{}}",
      "{\"arguments\":{},\"extra\":1}"
    ]

    cases =
      Enum.map(invalid, &{&1, "tool_calls"}) ++
        Enum.map(
          ["length", "content_filter", "incomplete", "unknown", nil],
          &{"{\"arguments\":{}}", &1}
        )

    for {args, finish} <- cases, layout <- [:name, :empty, :full] do
      {url, peer} = scripted([Map.put(reply([call(args)], finish), :layout, layout)])

      assert [{:error, error}] =
               ExAgent.run_stream(ExAgent.new(model: model(url), tools: [tool()]), "go")
               |> Enum.to_list()

      assert %ExAgent.RunError{} = error
      assert error.partial.request_count == 1
      assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
      refute_receive {:script_request, ^peer, _, _}, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  test "explicit stock argument loss rejects even a schema-valid fallback map without another Model request" do
    for layout <- [{:suffix, " \n\t"}, {:suffix, "!"}, :missing] do
      {url, peer} =
        scripted([Map.put(reply([call(~s({"arguments":{"value":7}}))]), :layout, layout)])

      assert [
               {:error,
                %ExAgent.RunError{
                  reason:
                    {:model_request_failed,
                     %ExAgent.RequestError{reason: :invalid_tool_arguments}},
                  partial: partial
                }}
             ] =
               ExAgent.run_stream(ExAgent.new(model: model(url), tools: [tool()]), "go")
               |> Enum.to_list()

      assert partial.request_count == 1
      assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
      refute_receive {:script_request, ^peer, _, _}, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  test "interleaved empty-start calls preserve identities while duplicate IDs reject the whole batch" do
    for duplicate? <- [false, true] do
      second_id = if duplicate?, do: "call-stream", else: "call-second"

      calls = [
        call(~s({"arguments":{"value":7}})),
        Map.put(call(~s({"arguments":{"value":8}})), "id", second_id)
      ]

      first = reply(calls) |> Map.put(:layout, :empty) |> Map.put(:interleaved, true)
      replies = if duplicate?, do: [first], else: [first, reply([], "stop", "done")]
      {url, peer} = scripted(replies)

      result =
        ExAgent.run_stream(ExAgent.new(model: model(url), tools: [tool()]), "go")
        |> Enum.to_list()

      if duplicate? do
        assert [
                 {:error,
                  %ExAgent.RunError{
                    reason:
                      {:model_request_failed,
                       %ExAgent.RequestError{reason: :invalid_tool_call_ids}}
                  }}
               ] = result

        refute_receive {:effect, _, _}, 0
      else
        assert {:result, %{request_count: 2, tool_calls: 2} = completed} = List.last(result)
        assert_receive {:effect, "call-stream", %{"value" => 7}}
        assert_receive {:effect, "call-second", %{"value" => 8}}
        refute_receive {:effect, _, _}, 0
        assert Message.from_json(Message.to_json(completed.messages)) == {:ok, completed.messages}
        assert_receive {:script_request, ^peer, 1, payload}
        assistant = Enum.find(payload["messages"], &(&1["role"] == "assistant"))

        assert Map.new(
                 assistant["tool_calls"],
                 &{&1["id"], Jason.decode!(&1["function"]["arguments"])}
               ) == %{
                 "call-stream" => %{"arguments" => %{"value" => 7}},
                 "call-second" => %{"arguments" => %{"value" => 8}}
               }
      end

      assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
      refute_receive {:script_request, ^peer, _, _}, 0
    end
  end

  test "reconstructed calls still validate effective hook arguments and identity before permissions and effects" do
    schema = %{
      "type" => "object",
      "properties" => %{"value" => %{"type" => "integer"}},
      "required" => ["value"],
      "additionalProperties" => false
    }

    for rewrite <- [:bad, :id, :valid], action <- [:allow, :deny] do
      first = Map.put(reply([call(~s({"arguments":{"value":7}}))]), :layout, :empty)
      {url, peer} = scripted([first, reply([], "stop", "done")])

      agent =
        ExAgent.new(
          model: model(url),
          tools: [%{tool() | parameters_json_schema: schema}],
          capabilities: [%AdmissionHook{rewrite: rewrite}]
        )

      ExAgent.run(agent, "go",
        stream_text: true,
        deps: %{owner: self()},
        permissions: ExAgent.Permissions.new!(default: action)
      )

      assert_receive {:admission_hook, %{"value" => 7}}

      if rewrite == :valid and action == :allow do
        assert_receive {:effect, "call-stream", %{"value" => 9}}
      end

      refute_receive {:effect, _, _}, 0
      assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
    end
  end

  test "reconstructed diagnostics survive persisted approval and resume without duplicate Model or tool effects" do
    start_supervised!({ExAgent.Store.ETS, table: __MODULE__})
    store = ExAgent.Store.scoped({ExAgent.Store.ETS, __MODULE__}, "admission")

    config = %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      definition: %{"id" => "admission", "version" => "1"},
      policy: %{"id" => "approval", "version" => "1"},
      model_ref: %{"id" => "stock", "version" => "1"},
      model_codec: %{dump: fn _ -> {:ok, %{}} end, load: fn model, %{} -> {:ok, model} end}
    }

    {url, peer} =
      scripted([
        Map.put(reply([call(~s({"arguments":{"value":7}}))]), :layout, :empty),
        reply([], "stop", "done")
      ])

    agent = ExAgent.new(model: model(url), tools: [tool()])

    opts = [
      continuation: config,
      permissions: ExAgent.Permissions.new!(default: :ask),
      stream_text: true
    ]

    assert {:ok, %{status: :paused, request_count: 1} = paused} = ExAgent.run(agent, "go", opts)
    assert_receive {:script_request, ^peer, 0, %{"stream" => true}}
    refute_receive {:script_request, ^peer, _, _}, 0
    refute_receive {:effect, _, _}, 0
    assert Message.from_json(Message.to_json(paused.messages)) == {:ok, paused.messages}
    assert {:ok, %{record: record}} = ExAgent.Continuation.get(store, "conversation")
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    assert {:ok, %{record: approved}} =
             ExAgent.Continuation.decide(store, "conversation", :approve,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "approve",
               approval_id: id,
               payload_hash: approval["payload_hash"],
               actor: :trusted,
               authorize: fn :trusted, :approve, _ -> {:ok, "human"} end
             )

    reference = %{paused.continuation | revision: approved["revision"]}

    assert {:ok, %{status: :succeeded, request_count: 2, tool_calls: 1} = result} =
             ExAgent.resume(agent, reference, opts)

    assert_receive {:effect, "call-stream", %{"value" => 7}}
    assert_receive {:script_request, ^peer, 1, payload}
    assistant = Enum.find(payload["messages"], &(&1["role"] == "assistant"))

    assert [%{"id" => "call-stream", "function" => %{"arguments" => args}}] =
             assistant["tool_calls"]

    assert Jason.decode!(args) == %{"arguments" => %{"value" => 7}}

    [call] =
      result.messages
      |> Enum.filter(&match?(%Message.Response{}, &1))
      |> Enum.flat_map(&Message.Response.tool_calls/1)

    assert call.metadata["invalid_arguments"] == true
    assert call.metadata["raw_arguments"] == ""
    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
    assert {:error, _} = ExAgent.resume(agent, reference, opts)
    refute_receive {:effect, _, _}, 0
    refute_receive {:script_request, ^peer, _, _}, 0
  end

  test "empty logical tool control executes once and Ecto validates embed null and corrective retry" do
    {empty_url, _} =
      scripted([Map.put(reply([call("{\"arguments\":{}}", "final_result")]), :layout, :empty)])

    empty_agent =
      ExAgent.new(model: model(empty_url), output_type: EmptyOutput, output_mode: :tool)

    assert [{:result, %{output: %EmptyOutput{}, request_count: 1}}] =
             ExAgent.run_stream(empty_agent, "go") |> Enum.to_list()

    {url, _} =
      scripted([
        Map.put(reply([call("{\"arguments\":{}}")]), :layout, :prefix),
        reply([], "stop", "done")
      ])

    assert {:ok, _} =
             ExAgent.run(ExAgent.new(model: model(url), tools: [tool()]), "go", stream_text: true)

    assert_receive {:effect, "call-stream", %{}}
    refute_receive {:effect, _, _}, 0

    for attrs <- [
          %{"value" => nil, "child" => nil},
          %{"value" => "good", "child" => %{"enabled" => true}}
        ] do
      wire = Jason.encode!(%{"arguments" => attrs})
      bad = Jason.encode!(%{"arguments" => %{"value" => "bad"}})

      {url, peer} =
        scripted([
          Map.put(reply([call(bad, "final_result")]), :layout, :empty),
          Map.put(reply([call(wire, "final_result")]), :layout, :prefix)
        ])

      agent = ExAgent.new(model: model(url), output_type: TypedOutput, output_mode: :tool)
      assert [{:result, result}] = ExAgent.run_stream(agent, "go") |> Enum.to_list()
      assert %TypedOutput{} = result.output
      assert result.output.value == attrs["value"]
      assert result.request_count == 2
      assert_receive {:script_request, ^peer, 0, _}
      assert_receive {:script_request, ^peer, 1, payload}
      assert Enum.any?(payload["messages"], &(&1["role"] == "tool"))
    end
  end

  test "response byte and chunk budgets stop finite streams before terminal" do
    for {text, count, expected} <- [
          {String.duplicate("x", 32 * 1024), 34, :response_bytes},
          {"x", 4098, :chunks}
        ] do
      {url, peer} = peer()
      task = Task.async(fn -> Enum.to_list(stream(model(url))) end)
      assert_receive {:request, ^peer, _}, 5000
      bytes = String.duplicate(frame(%{"content" => text}), count)
      assert byte_size(bytes) < 2 * 1024 * 1024
      assert :ok = command(peer, {:send, bytes})
      events = Task.await(task)

      assert {:error, %ExAgent.RequestError{reason: {:stream_limit, ^expected}}} =
               List.last(events)

      refute Enum.any?(events, &match?({:response, _, _}, &1))
      assert {:error, :closed} = command(peer, :closed)
    end
  end

  test "explicit unsupported stream settings reject before IO" do
    {url, peer} = peer()

    assert [{:error, %ExAgent.RequestError{reason: {:invalid_option, :stream_max_tokens}}}] =
             Model.request_stream(
               model(url),
               [],
               %ModelSettings{max_tokens: 4097},
               %ModelRequestParameters{}
             )
             |> Enum.to_list()

    assert [{:error, {:unsupported, :streaming}}] =
             stream(model(url, tool_profile: nil)) |> Enum.to_list()

    refute_receive {:request, ^peer, _}, 20
  end

  def telemetry_barrier(_, _, _, {owner, block?}) do
    send(owner, {:producer, self()})
    if block?, do: receive(do: (:release -> :ok))
  end

  defp observe_producers(block? \\ false) do
    id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        id,
        [:req_llm, :request, :start],
        &__MODULE__.telemetry_barrier/4,
        {self(), block?}
      )

    on_exit(fn -> :telemetry.detach(id) end)
    id
  end

  defp await_value(fun, remaining \\ 2000) do
    case fun.() do
      nil when remaining > 0 ->
        Process.sleep(1)
        await_value(fun, remaining - 1)

      nil ->
        flunk("barrier not reached")

      value ->
        value
    end
  end

  defp guardian(owner) do
    await_value(fn ->
      case Process.info(owner, :monitors) do
        {:monitors, [{:process, guardian}]} -> guardian
        _ -> nil
      end
    end)
  end

  defp resume_on_exit(pid) do
    on_exit(fn ->
      try do
        :erlang.resume_process(pid)
      catch
        :error, :badarg -> :ok
      end
    end)
  end

  test "owner death during handle registration reaps guardian producer metadata and socket" do
    observe_producers(true)
    {url, peer} = peer()
    owner = spawn(fn -> Enum.to_list(stream(model(url))) end)
    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:producer, producer}, 5000
    guardian = guardian(owner)
    true = :erlang.suspend_process(guardian)
    resume_on_exit(guardian)
    send(producer, :release)

    public_stream =
      await_value(fn ->
        {:messages, messages} = Process.info(guardian, :messages)

        Enum.find_value(messages, fn
          {_, :register, %ReqLLM.StreamResponse{} = response} -> response
          _ -> nil
        end)
      end)

    monitors =
      Enum.map([producer, guardian, public_stream.metadata_handle], &{&1, Process.monitor(&1)})

    assert_receive {:request, ^peer, _}, 2000
    Process.exit(owner, :kill)
    true = :erlang.resume_process(guardian)
    for {pid, monitor} <- monitors, do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2000)
    assert {:error, :closed} = command(peer, :closed)
  end

  test "queued final result obeys completion timestamp even when guardian is descheduled" do
    observe_producers()
    parent = self()

    for timely? <- [true, false] do
      {url, peer} = peer()

      task =
        Task.async(fn ->
          Enum.map(stream(model(url, total_timeout: 1000)), fn event ->
            if match?({:text_delta, _}, event), do: send(parent, :deadline_delta)
            event
          end)
        end)

      assert_receive {:producer, producer}, 5000
      assert_receive {:request, ^peer, _}, 2000
      guardian = guardian(task.pid)
      producer_monitor = Process.monitor(producer)
      # One callback proves registration was acknowledged before guardian suspension.
      assert :ok = command(peer, {:send, frame(%{"content" => "provisional"})})

      assert_receive :deadline_delta, 500

      true = :erlang.suspend_process(guardian)
      resume_on_exit(guardian)

      if timely? do
        assert :ok = command(peer, {:send, terminal()})
        assert :ok = command(peer, :finish)
        assert_receive {:DOWN, ^producer_monitor, :process, ^producer, :normal}, 700
      end

      timer = make_ref()
      Process.send_after(self(), {timer, :past}, 1100)
      assert_receive {^timer, :past}, 1500

      unless timely? do
        assert :ok = command(peer, {:send, terminal()})
        assert :ok = command(peer, :finish)
        assert_receive {:DOWN, ^producer_monitor, :process, ^producer, :normal}, 700
      end

      true = :erlang.resume_process(guardian)
      events = Task.await(task)

      if timely?,
        do: assert(match?({:response, _, _}, List.last(events))),
        else:
          assert(
            match?({:error, %ExAgent.RequestError{reason: {:timeout, :total}}}, List.last(events))
          )
    end
  end

  test "total and receive timeouts cannot authorize a complete tool JSON in an unfinished interaction" do
    for {total, receive_timeout} <- [{150, 5000}, {5000, 100}] do
      {url, peer} = peer()

      agent =
        ExAgent.new(
          model:
            model(url, total_timeout: total, http_options: [receive_timeout: receive_timeout]),
          tools: [tool()]
        )

      task = Task.async(fn -> Enum.to_list(ExAgent.run_stream(agent, "go")) end)
      assert_receive {:request, ^peer, _}, 5000
      bytes = frame(%{"tool_calls" => [Map.put(call("{\"arguments\":{}}"), "index", 0)]})
      assert :ok = command(peer, {:send, bytes})
      assert [{:error, %ExAgent.RunError{partial: partial}}] = Task.await(task)
      assert partial.request_count == 1
      refute_receive {:effect, _, _}, 0
      assert {:error, :closed} = command(peer, :closed)
    end
  end

  test "slow consumers retain one host delta, bounded producer materialization, and cleanup at concurrency 1 and 8" do
    observe_producers()

    for concurrency <- [1, 8] do
      parent = self()

      workers =
        for _ <- 1..concurrency do
          {url, peer} = peer()

          owner =
            spawn(fn ->
              {:suspended, event, next} =
                Enumerable.reduce(stream(model(url)), {:cont, nil}, fn event, _ ->
                  {:suspend, event}
                end)

              send(parent, {:suspended, self(), event})
              receive do: (:halt -> next.({:halt, nil}))
            end)

          on_exit(fn -> Process.exit(owner, :kill) end)
          assert_receive {:producer, producer}, 5000
          assert_receive {:request, ^peer, _}, 5000
          {owner, producer, guardian(owner), peer}
        end

      for {owner, _, _, peer} <- workers do
        assert :ok =
                 command(
                   peer,
                   {:send,
                    String.duplicate(frame(%{"content" => String.duplicate("s", 4096)}), 32)}
                 )

        assert_receive {:suspended, ^owner, {:text_delta, text}}, 2000
        assert byte_size(text) == 4096
      end

      measures =
        for {owner, producer, guardian, peer} <- workers do
          {:message_queue_len, queue} = Process.info(owner, :message_queue_len)
          {:memory, memory} = Process.info(producer, :memory)
          {:messages, messages} = Process.info(producer, :messages)
          assert queue == 0
          assert length(messages) <= 1
          # Finite observation threshold, distinct from the serialized-byte contract.
          assert memory < 4 * 1024 * 1024
          monitors = Enum.map([owner, producer, guardian], &{&1, Process.monitor(&1)})
          send(owner, :halt)

          for {pid, monitor} <- monitors,
              do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2000)

          assert {:error, :closed} = command(peer, :closed)
          %{producer_heap_bytes: memory, owner_queue: queue}
        end

      IO.inspect(%{concurrency: concurrency, measurements: measures},
        label: "R14 finite slow-consumer"
      )
    end
  end

  test "shared public RunStream progress bridge retains only one unacknowledged snapshot" do
    parent = self()
    marker = make_ref()

    on_event = fn event ->
      if event.type == :text_delta and Process.put(marker, true) != true do
        send(parent, {:first_public_delta, self()})
        receive do: (:release -> :ok)
      end
    end

    agent = ExAgent.new(model: %ExAgent.Models.Test{label: String.duplicate("word ", 100)})

    task =
      Task.async(fn -> ExAgent.run_stream(agent, "go", on_event: on_event) |> Enum.to_list() end)

    assert_receive {:first_public_delta, worker}, 5000
    guardian = guardian(task.pid)
    true = :erlang.suspend_process(guardian)
    resume_on_exit(guardian)
    send(worker, :release)

    await_value(fn ->
      {:message_queue_len, length} = Process.info(guardian, :message_queue_len)
      if length > 0, do: true
    end)

    Process.sleep(20)
    {:messages, pending} = Process.info(guardian, :messages)

    progress =
      Enum.filter(pending, &(is_tuple(&1) and tuple_size(&1) >= 3 and elem(&1, 1) == :progress))

    assert length(progress) == 1
    [{ref, :progress, _, _}] = progress
    send(worker, {ref, :progress_ack, make_ref()})
    Process.sleep(10)
    {:messages, still_pending} = Process.info(guardian, :messages)

    assert Enum.count(
             still_pending,
             &(is_tuple(&1) and tuple_size(&1) == 4 and elem(&1, 1) == :progress)
           ) == 1

    true = :erlang.resume_process(guardian)
    assert {:result, result} = task |> Task.await() |> List.last()
    assert result.output == String.duplicate("word ", 100)
  end

  test "public RunStream guardian death cancels linked work for Test and real ReqLLM" do
    for mode <- [:test, :req_llm] do
      parent = self()
      {url, peer} = peer()

      agent =
        ExAgent.new(
          model: if(mode == :test, do: %ExAgent.Models.Test{label: "one two"}, else: model(url))
        )

      on_event = fn event ->
        if event.type == :text_delta do
          send(parent, {:at_delta, self()})
          receive do: (:release -> :ok)
        end
      end

      owner =
        spawn(fn ->
          try do
            Enum.to_list(ExAgent.run_stream(agent, "go", on_event: on_event))
          catch
            :exit, reason -> send(parent, {:consumer_exit, reason})
          end
        end)

      on_exit(fn -> Process.exit(owner, :kill) end)

      if mode == :req_llm do
        assert_receive {:request, ^peer, _}, 5000
        assert :ok = command(peer, {:send, frame(%{"content" => "one"})})
      end

      assert_receive {:at_delta, worker}, 5000
      guardian = guardian(owner)
      monitor = Process.monitor(worker)
      Process.exit(guardian, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 2000
      assert_receive {:consumer_exit, {:stream_owner_failed, :killed}}, 2000
      if mode == :req_llm, do: assert({:error, :closed} == command(peer, :closed))
    end
  end

  test "owner kill while public progress ACK is pending releases Test and ReqLLM without effects" do
    for mode <- [:test, :req_llm] do
      parent = self()
      {url, peer} = peer()
      marker = make_ref()

      on_event = fn event ->
        if event.type == :text_delta and Process.put(marker, true) != true do
          send(parent, {:at_delta, self()})
          receive do: (:release -> :ok)
        end
      end

      agent =
        ExAgent.new(
          model:
            if(mode == :test, do: %ExAgent.Models.Test{label: "one two three"}, else: model(url)),
          tools: [tool()]
        )

      owner =
        spawn(fn -> ExAgent.run_stream(agent, "go", on_event: on_event) |> Enum.to_list() end)

      on_exit(fn -> Process.exit(owner, :kill) end)

      if mode == :req_llm do
        assert_receive {:request, ^peer, _}, 5000
        assert :ok = command(peer, {:send, frame(%{"content" => "one"})})
      end

      assert_receive {:at_delta, worker}, 5000
      guardian = guardian(owner)
      true = :erlang.suspend_process(guardian)
      resume_on_exit(guardian)
      send(worker, :release)

      if mode == :req_llm do
        assert :ok =
                 command(
                   peer,
                   {:send,
                    frame(%{"content" => "two"}) <>
                      frame(%{"tool_calls" => [Map.put(call("{\"arguments\":{}}"), "index", 0)]}) <>
                      terminal("tool_calls")}
                 )
      end

      await_value(fn ->
        {:messages, messages} = Process.info(guardian, :messages)
        Enum.find(messages, &(is_tuple(&1) and tuple_size(&1) == 4 and elem(&1, 1) == :progress))
      end)

      monitors = Enum.map([worker, guardian], &{&1, Process.monitor(&1)})
      Process.exit(owner, :kill)
      true = :erlang.resume_process(guardian)

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2000)

      refute_receive {:effect, _, _}, 0
      if mode == :req_llm, do: assert({:error, :closed} == command(peer, :closed))
    end
  end

  if Code.ensure_loaded?(:otel_tracer) do
    def telemetry_context(_, _, _, owner),
      do: send(owner, {:native_context, :otel_tracer.current_span_ctx()})

    test "model producer preserves native trace context with isolation" do
      id = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          id,
          [:req_llm, :request, :start],
          &__MODULE__.telemetry_context/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(id) end)
      before = :otel_tracer.current_span_ctx()

      for value <- [101, 202] do
        context = :otel_tracer.from_remote_span(value, value, 1)
        {url, _} = scripted([reply([], "stop", "context")])
        native = :otel_tracer.set_current_span(%{}, context)
        captured = %ExAgent.Observability.OpenTelemetry.Context{native: native}

        events =
          ExAgent.Observability.OpenTelemetry.with_context(captured, fn ->
            stream(model(url)) |> Enum.to_list()
          end)

        assert match?({:response, _, _}, List.last(events))
        assert_receive {:native_context, ^context}
        assert :otel_tracer.current_span_ctx() == before
      end
    end
  end

  test "stream requests share the existing exact concurrency admission and release their scope slot" do
    {url, peer} = peer()
    first_model = model(url)

    {:ok, scope} =
      ExAgent.ExecutionScope.start("stream-root", first_model, max_concurrent_requests: 1)

    on_exit(fn -> ExAgent.ExecutionScope.stop(scope) end)
    parent = %{execution_scope: scope}

    task =
      Task.async(fn ->
        ExAgent.run_child(parent, ExAgent.new(model: first_model), "go", stream_text: true)
      end)

    assert_receive {:request, ^peer, _}, 5000
    {other_url, other_peer} = scripted([reply([], "stop", "released")])
    other = ExAgent.new(model: model(other_url))

    assert {:error, %ExAgent.RunError{reason: {:concurrency_limit_exceeded, 1}}} =
             ExAgent.run_child(parent, other, "go", stream_text: true)

    refute_receive {:script_request, ^other_peer, _, _}, 20
    assert :ok = command(peer, {:send, frame(%{"content" => "first"}) <> terminal()})
    assert :ok = command(peer, :finish)
    assert {:ok, %{output: "first"}} = Task.await(task)

    assert {:ok, %{output: "released"}} =
             ExAgent.run_child(parent, other, "go", stream_text: true)

    assert_receive {:script_request, ^other_peer, 0, _}
    assert {:ok, %{request_count: 2}} = ExAgent.ExecutionScope.snapshot(scope)
  end

  def telemetry_trap(_, _, _, owner) do
    Process.flag(:trap_exit, true)
    send(owner, {:trapping_producer, self()})
    receive do: (:release -> :ok)
  end

  @tag :shutdown_guard
  test "a real producer trapping exits is forcibly reaped before and during public registration" do
    for mode <- [:timeout, :owner_before_registration, :owner_during_registration] do
      id = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(id, [:req_llm, :request, :start], &__MODULE__.telemetry_trap/4, self())

      on_exit(fn -> :telemetry.detach(id) end)
      {url, peer} = peer()
      parent = self()
      timeout = if mode == :timeout, do: 200, else: 5000

      owner =
        spawn(fn ->
          send(
            parent,
            {:trapped_result, Enum.to_list(stream(model(url, total_timeout: timeout)))}
          )
        end)

      on_exit(fn -> Process.exit(owner, :kill) end)
      assert_receive {:trapping_producer, producer}, 5000
      guardian = guardian(owner)
      monitors = Enum.map([producer, guardian, owner], &{&1, Process.monitor(&1)})

      on_exit(fn ->
        Process.exit(producer, :kill)
        Process.exit(guardian, :kill)
      end)

      assert_receive {:request, ^peer, _}, 2000

      if mode == :owner_during_registration do
        true = :erlang.suspend_process(guardian)
        resume_on_exit(guardian)
        send(producer, :release)

        public_stream =
          await_value(fn ->
            {:messages, messages} = Process.info(guardian, :messages)

            Enum.find_value(messages, fn
              {_, :register, %ReqLLM.StreamResponse{} = response} -> response
              _ -> nil
            end)
          end)

        metadata_monitor = Process.monitor(public_stream.metadata_handle)
        Process.exit(owner, :kill)
        true = :erlang.resume_process(guardian)
        assert_receive {:DOWN, ^metadata_monitor, :process, _, _}, 2000
      else
        if mode == :owner_before_registration, do: Process.exit(owner, :kill)
      end

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2000)

      if mode == :timeout,
        do:
          assert_receive(
            {:trapped_result, [{:error, %ExAgent.RequestError{reason: {:timeout, :total}}}]},
            2000
          )

      assert {:error, :closed} = command(peer, :closed)
      :telemetry.detach(id)
    end
  end
end

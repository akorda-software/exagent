System.put_env("G2_LOAD_ONLY", "1")
root = System.fetch_env!("G2_ROOT")
Code.require_file("g2.exs", System.get_env("G2_HARNESS_SOURCE") || root)
artifact = Path.join(root, System.get_env("G2_SYNTHETIC_NAME") || "synthetic-historical")
File.mkdir_p!(artifact)
System.put_env("G2_ARTIFACT_ROOT", artifact)

defmodule G2.TCP do
  def request(socket, bytes \\ "") do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, n] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(n) - byte_size(body)

        if missing > 0 do
          {:ok, rest} = :gen_tcp.recv(socket, missing, 5000)
          {Jason.decode!(body <> rest), byte_size(body <> rest)}
        else
          {Jason.decode!(body), byte_size(body)}
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        request(socket, bytes <> more)
    end
  end

  def frame(delta, finish \\ nil) do
    "data: " <>
      Jason.encode!(%{
        id: "synthetic-response",
        model: System.get_env("G2_REQUESTED_MODEL") || "openai/gpt-4o-mini",
        choices: [%{index: 0, delta: delta, finish_reason: finish}],
        usage: %{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30}
      }) <> "\n\n"
  end

  def call(name, args, id) do
    f = if args == :absent, do: %{name: name}, else: %{name: name, arguments: args}
    %{index: 0, id: id, type: "function", function: f}
  end

  def wire(payload, spec) do
    finish = Map.get(spec, :finish, "tool_calls")

    if payload["stream"] do
      data =
        if Map.has_key?(spec, :text) do
          frame(%{content: spec.text})
        else
          json = spec.json

          {initial, rest} =
            case Map.get(spec, :start, :name) do
              :name -> {:absent, json}
              :empty -> {"", json}
              :prefix -> {String.slice(json, 0, 1), String.slice(json, 1..-1//1)}
              :full -> {json, ""}
              :whitespace -> {json, " \n\t"}
              :suffix -> {json, "!"}
              :none -> {:absent, ""}
            end

          frame(%{tool_calls: [call(spec.name, initial, Map.get(spec, :id, "call-g2"))]}) <>
            Enum.map_join(String.codepoints(rest), fn part ->
              frame(%{tool_calls: [%{index: 0, function: %{arguments: part}}]})
            end)
        end

      terminal = if finish, do: frame(%{}, finish) <> "data: [DONE]\n\n", else: ""
      {"text/event-stream", data <> terminal}
    else
      message =
        if Map.has_key?(spec, :text),
          do: %{role: "assistant", content: spec.text},
          else: %{
            role: "assistant",
            content: nil,
            tool_calls: [
              Map.delete(call(spec.name, spec.json, Map.get(spec, :id, "call-g2")), :index)
            ]
          }

      message = Map.merge(message, Map.get(spec, :message_extra, %{}))

      {"application/json",
       Jason.encode!(%{
         id: "synthetic-response",
         model: System.get_env("G2_REQUESTED_MODEL") || "openai/gpt-4o-mini",
         choices: [%{index: 0, message: message, finish_reason: finish}],
         usage: %{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30}
       })}
    end
  end

  def start(specs) do
    owner = self()
    ref = make_ref()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    {pid, mon} =
      spawn_monitor(fn ->
        for spec <- specs do
          {:ok, socket} = :gen_tcp.accept(listener, 8000)
          {payload, bytes} = request(socket)

          if System.get_env("G2_BOUNDED_INPUT") == "1" do
            true = bytes <= 16_384 and length(payload["messages"]) <= 10

            File.write!(
              G2.path("wire-payloads.jsonl"),
              Jason.encode!(%{bytes: bytes, payload: payload}) <> "\n",
              [:append]
            )
          end

          send(owner, {ref, payload})
          {type, body} = wire(payload, spec)

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nConnection: close\r\n\r\n" <> body
            )

          :gen_tcp.close(socket)
        end

        :gen_tcp.close(listener)
      end)

    {G2.model("synthetic-not-a-credential", "http://127.0.0.1:#{port}/v1"),
     {listener, pid, mon, ref}}
  end

  def finish({listener, pid, mon, ref}) do
    :gen_tcp.close(listener)
    if Process.alive?(pid), do: Process.exit(pid, :kill)

    receive do
      {:DOWN, ^mon, :process, ^pid, _} -> :ok
    after
      1000 -> raise "TCP cleanup missing"
    end

    collect(ref, [])
  end

  def collect(ref, acc) do
    receive do
      {^ref, payload} -> collect(ref, [payload | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  def specs(kind) do
    case kind do
      :text ->
        [%{text: "G2_OK", finish: "stop"}]

      :tools ->
        [
          %{name: "record_marker", json: ~s({"arguments":{"marker":"seven"}})},
          %{text: "RECEIPT_SEVEN", finish: "stop"}
        ]

      :ecto ->
        [%{name: "final_result", json: ~s({"arguments":{"label":"accepted","count":7}})}]

      :native ->
        [%{text: ~s({"label":"accepted","count":7}), finish: "stop"}]

      :empty ->
        [%{name: "final_result", json: ~s({"arguments":{}})}]

      :length ->
        [%{text: "1\n2\n3\n4\n5", finish: "length"}]
    end
  end

  def nominal do
    {:ok, ledger} = Agent.start_link(fn -> %{count: 0} end, name: G2.Ledger)

    records =
      for {name, kind, _} = c <- G2.cases() do
        Agent.update(ledger, fn _ -> %{count: 0} end)
        {model, peer} = start(specs(kind))
        r = G2.one(c, model)
        payloads = finish(peer)
        true = r.accepted
        true = length(payloads) == r.admissions

        if System.get_env("G2_NONE_MODEL") == "1" do
          true =
            Enum.all?(
              payloads,
              &(&1["reasoning_effort"] == "none" and not Map.has_key?(&1, "temperature") and
                  not Map.has_key?(&1, "max_tokens"))
            )

          true =
            Enum.all?(
              payloads,
              &(&1["max_completion_tokens"] == if(kind == :length, do: 16, else: 256))
            )
        else
          true = Enum.all?(payloads, &(&1["temperature"] == 0.0))
          if kind == :length, do: true = hd(payloads)["max_tokens"] == 16
        end

        %{name: name, requests: length(payloads), effects: r.effects, accepted: true}
      end

    Agent.stop(ledger)
    records
  end

  def shapes do
    adapted = System.get_env("G2_EXPECT_ADAPTED") == "1"
    valid = ~s({"arguments":{"marker":"seven"}})

    inputs = [
      {"valid", valid, :name, "tool_calls", true},
      {"historical_empty", valid, :empty, "tool_calls", true},
      {"historical_prefix", valid, :prefix, "tool_calls", true},
      {"lost_whitespace", valid, :whitespace, "tool_calls", false},
      {"lost_suffix", valid, :suffix, "tool_calls", false},
      {"array", "[]", :name, "tool_calls", false},
      {"array_object", "[{}]", :name, "tool_calls", false},
      {"scalar", "7", :name, "tool_calls", false},
      {"null", "null", :name, "tool_calls", false},
      {"empty_fallback", "{}", :name, "tool_calls", false},
      {"empty_string", "", :empty, "tool_calls", false},
      {"missing_fragments", "", :none, "tool_calls", false},
      {"truncated", ~s({"arguments":{"marker":"seven"}), :name, "tool_calls", false},
      {"logical_schema", ~s({"arguments":{"marker":7}}), :name, "tool_calls", false},
      {"outer_extra", ~s({"arguments":{"marker":"seven"},"extra":1}), :name, "tool_calls", false},
      {"length", valid, :name, "length", false},
      {"filter", valid, :name, "content_filter", false},
      {"unknown", valid, :name, "unknown", false},
      {"eof", valid, :name, nil, false}
    ]

    for surface <- [:stream_text, :stream],
        {name, json, layout, terminal, logical_valid} <- inputs do
      # Historical bytes are a retained red control, never qualification of the new policy.
      expected = logical_valid and (adapted or layout == :name)
      spec = %{name: "record_marker", json: json, start: layout, finish: terminal}
      next = if expected, do: [%{text: "RECEIPT_SEVEN", finish: "stop"}], else: []
      {model, peer} = start([spec | next])
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      agent =
        ExAgent.new(
          model: model,
          tools: [G2.tool(counter)],
          output_retries: 0,
          model_settings: [
            temperature: if(System.get_env("G2_NONE_MODEL") == "1", do: nil, else: 0.0),
            max_tokens: 256
          ],
          usage_limits: %ExAgent.UsageLimits{request_limit: 2, tool_calls_limit: 1}
        )

      {result, events} = G2.execute(agent, "Synthetic marker seven", surface)
      effects = Agent.get(counter, & &1)
      Agent.stop(counter)
      payloads = finish(peer)

      checks =
        if expected,
          do: G2.check(:tools, result, effects),
          else: %{
            rejected: match?({:error, _}, result),
            zero_effects: effects == 0,
            one_request: length(payloads) == 1
          }

      calls =
        case result do
          {:ok, r} ->
            r.messages
            |> Enum.filter(&match?(%ExAgent.Message.Response{}, &1))
            |> Enum.flat_map(&ExAgent.Message.Response.tool_calls/1)

          _ ->
            []
        end

      if expected and layout in [:empty, :prefix] do
        true = Enum.any?(calls, &(&1.metadata["invalid_arguments"] == true))
        true = Enum.any?(calls, &(&1.metadata["unparseable_arguments"] == true))
      end

      record = %{
        name: name,
        surface: surface,
        expected_admitted: expected,
        requests: length(payloads),
        effects: effects,
        checks: checks,
        accepted: Enum.all?(Map.values(checks)),
        result: G2.summarize(result),
        event_tags: Enum.map(events, &elem(&1, 0))
      }

      File.write!(G2.path("shape-results.jsonl"), Jason.encode!(record) <> "\n", [:append])
      true = record.accepted
      Map.take(record, [:name, :surface, :requests, :effects, :accepted, :expected_admitted])
    end
  end
end

unless System.get_env("G2_TCP_LIBRARY") == "1" do
  nominal = G2.TCP.nominal()
  shapes = G2.TCP.shapes()

  report = %{
    phase: "offline harness validation",
    adapted: System.get_env("G2_EXPECT_ADAPTED") == "1",
    nominal: nominal,
    shapes: shapes,
    real_requests: 0,
    inference_cost_usd: 0,
    synthetic_requests: Enum.sum(Enum.map(nominal ++ shapes, & &1.requests)),
    effects: Enum.sum(Enum.map(nominal ++ shapes, & &1.effects))
  }

  File.write!(G2.path("summary.json"), Jason.encode!(report, pretty: true))
  IO.puts(Jason.encode!(Map.drop(report, [:nominal, :shapes])))
end

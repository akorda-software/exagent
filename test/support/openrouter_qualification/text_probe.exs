System.put_env("G2_TCP_LIBRARY", "1")
System.put_env("G2_SYNTHETIC_NAME", "text-preflight")

Code.require_file(
  "synthetic.exs",
  System.get_env("G2_HARNESS_SOURCE") || System.fetch_env!("G2_ROOT")
)

defmodule G2.TextAdmission do
  use ExAgent.Capability

  def before_model_request(_, state) do
    Agent.get_and_update(G2.TextLedger, fn data ->
      next = %{data | count: data.count + 1, reserved_usd: data.reserved_usd + data.unit}
      if next.count > 80 or next.reserved_usd > 5, do: raise("multimodel budget exhausted")

      File.write!(
        Path.join(System.fetch_env!("G2_ROOT"), "text-admissions.json"),
        Jason.encode!(next)
      )

      {:ok, next}
    end)

    state
  end
end

defmodule G2.TextProbe do
  def model(id, provider, key, url) do
    ExAgent.Models.ReqLLM.new(
      model: %{
        provider: provider,
        id: id,
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: true}},
        extra: %{wire: %{protocol: "openai_chat"}}
      },
      api_key: key,
      base_url: url,
      total_timeout: 45_000
    )
  end

  def run(model, live) do
    agent =
      ExAgent.new(
        model: model,
        output_retries: 0,
        capabilities: if(live, do: [G2.TextAdmission], else: []),
        model_settings: [max_tokens: 256],
        usage_limits: %ExAgent.UsageLimits{request_limit: 1, tool_calls_limit: 0}
      )

    ExAgent.run(agent, "Reply with exactly G2_OK and nothing else.")
  end

  def project(result) do
    {status, r} = result
    reason = if status == :error, do: reason_tag(r.reason), else: nil
    r = if status == :error, do: r.partial, else: r
    responses = Enum.filter(Map.get(r, :messages, []), &match?(%ExAgent.Message.Response{}, &1))

    %{
      status: status,
      reason: reason,
      output_exact: status == :ok and String.trim(r.output) == "G2_OK",
      request_count: r.request_count,
      tool_calls: r.tool_calls,
      usage: Map.from_struct(r.usage),
      message_roundtrip:
        ExAgent.Message.from_json(ExAgent.Message.to_json(r.messages)) == {:ok, r.messages},
      responses:
        Enum.map(responses, fn response ->
          %{
            finish_reason: response.finish_reason,
            thinking_parts:
              Enum.count(response.parts, &match?(%ExAgent.Message.Part.Thinking{}, &1)),
            reasoning_details:
              Enum.map(response.continuation["reasoning_details"] || [], fn detail ->
                Map.take(detail, ["type", "id", "provider", "format", "index"])
              end)
          }
        end)
    }
  end

  def reason_tag({:model_request_failed, %ExAgent.RequestError{reason: reason}}),
    do: reason_tag(reason)

  def reason_tag({:incomplete_response, finish}),
    do: %{kind: :incomplete_response, finish: finish}

  def reason_tag({:unsupported, reason}), do: %{kind: :unsupported, detail: reason}
  def reason_tag(reason) when is_atom(reason), do: reason
  def reason_tag(_), do: :other_public_error

  def preflight(plan) do
    results =
      for config <- plan["models"], provider <- [:openai, :openrouter] do
        extra = %{
          reasoning: "SYNTHETIC_REASONING",
          reasoning_details: [
            %{
              type: "reasoning.text",
              text: "SYNTHETIC_REASONING",
              id: "reason-synthetic",
              format: "unknown",
              index: 0
            }
          ]
        }

        {endpoint, peer} = G2.TCP.start([%{text: "G2_OK", finish: "stop", message_extra: extra}])
        model = model(config["id"], provider, "synthetic-not-a-credential", endpoint.base_url)
        result = run(model, false)
        payloads = G2.TCP.finish(peer)
        projection = project(result)

        if provider == :openrouter do
          true = projection.output_exact and projection.message_roundtrip
          [payload] = payloads
          true = payload["max_tokens"] == 256 and payload["model"] == config["id"]
          true = not Map.has_key?(payload, "temperature")
          true = not Map.has_key?(payload, "reasoning_effort")
          true = not Map.has_key?(payload, "reasoning")
          true = (payload["tools"] || []) == []
          {:ok, r} = result
          response = Enum.find(r.messages, &match?(%ExAgent.Message.Response{}, &1))
          details = response.continuation["reasoning_details"]
          true = length(details) == 1
          true = hd(details)["text"] == "SYNTHETIC_REASONING"
        else
          true = projection.status == :error and payloads == []
        end

        %{
          model: config["id"],
          provider: provider,
          requests: length(payloads),
          result: projection,
          payload:
            Enum.map(
              payloads,
              &Map.take(&1, ["model", "max_tokens", "temperature", "reasoning", "tools"])
            )
        }
      end

    record = %{
      cases: results,
      real_requests: 0,
      synthetic_requests: 2,
      effects: 0,
      accepted: true
    }

    File.write!(G2.path("summary.json"), Jason.encode!(record, pretty: true))
    IO.puts(Jason.encode!(record, pretty: true))
  end

  def live(plan, id) do
    true = System.get_env("G2_TEXT_LIVE_AUTHORIZED") == "1"
    config = Enum.find(plan["models"], &(&1["id"] == id))
    true = not is_nil(config)
    root = System.fetch_env!("G2_ROOT")
    ledger_path = Path.join(root, "text-admissions.json")

    existing =
      if File.exists?(ledger_path),
        do: Jason.decode!(File.read!(ledger_path)),
        else: %{"count" => 17, "reserved_usd" => 0.425}

    {:ok, _} =
      Agent.start_link(
        fn ->
          %{
            count: existing["count"],
            reserved_usd: existing["reserved_usd"],
            unit: config["reserved_usd"]
          }
        end,
        name: G2.TextLedger
      )

    started = System.monotonic_time(:millisecond)

    result =
      run(
        model(
          id,
          :openrouter,
          System.fetch_env!("OPENROUTER_API_KEY"),
          "https://openrouter.ai/api/v1"
        ),
        true
      )

    projection = project(result)

    record = %{
      model: id,
      provider: :openrouter,
      surface: :buffered_text_only,
      time_utc: DateTime.utc_now(),
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      result: projection,
      effects: 0,
      admission_count: Agent.get(G2.TextLedger, & &1.count),
      accepted_text:
        projection.output_exact and projection.message_roundtrip and projection.request_count == 1,
      tools_profile: :not_qualified,
      reasoning_capability: true,
      max_tokens: 256
    }

    File.write!(Path.join(root, "text-results.jsonl"), Jason.encode!(record) <> "\n", [:append])
    IO.puts(Jason.encode!(record, pretty: true))
    if not record.accepted_text, do: System.halt(1)
  end
end

unless System.get_env("G2_TEXT_LIBRARY") == "1" do
  plan = Jason.decode!(File.read!(Path.join(System.fetch_env!("G2_ROOT"), "text-plan.json")))

  case System.argv() do
    [] -> G2.TextProbe.preflight(plan)
    [id] -> G2.TextProbe.live(plan, id)
  end
end

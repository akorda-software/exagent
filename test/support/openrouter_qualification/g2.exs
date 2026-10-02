Logger.configure(level: :emergency)

defmodule G2.Output do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field(:label, :string)
    field(:count, :integer)
  end

  def changeset(data, attrs) do
    data
    |> cast(attrs, [:label, :count])
    |> validate_required([:label, :count])
    |> validate_inclusion(:label, ["accepted"])
    |> validate_number(:count, equal_to: 7)
  end
end

defmodule G2.Empty do
  use Ecto.Schema
  @primary_key false
  embedded_schema do
  end

  def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [])
end

defmodule G2.Admission do
  use ExAgent.Capability

  def before_model_request(_, state) do
    Agent.get_and_update(G2.Ledger, fn ledger ->
      count = ledger.count + 1
      reserve = Map.get(ledger, :reserved_usd, 0.0) + Map.get(ledger, :unit, 0.025)

      if count > Map.get(ledger, :max_count, 30) or reserve > Map.get(ledger, :max_usd, 2),
        do: raise("G2 budget exhausted")

      updated = ledger |> Map.put(:count, count) |> Map.put(:reserved_usd, reserve)
      File.write!(G2.path("admissions.json"), Jason.encode!(updated))

      if System.get_env("G2_GLOBAL_LEDGER") do
        File.write!(System.fetch_env!("G2_GLOBAL_LEDGER"), Jason.encode!(updated))
      end

      {:ok, updated}
    end)

    state
  end
end

defmodule G2 do
  alias ExAgent.Message
  alias ExAgent.Message.{Response, Part}

  def path(name),
    do: Path.join(System.get_env("G2_ARTIFACT_ROOT") || System.fetch_env!("G2_ROOT"), name)

  def model(key, base_url \\ "https://openrouter.ai/api/v1") do
    base =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: "openai/gpt-4o-mini",
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
          extra: %{wire: %{protocol: "openai_chat"}}
        },
        api_key: key,
        base_url: base_url,
        tool_profile: :chat_tools_v1,
        output_profile: :chat_json_schema_v1,
        total_timeout: 45_000
      )

    if System.get_env("G2_NONE_MODEL") == "1" do
      catalog =
        Jason.decode!(File.read!(Path.join(System.fetch_env!("G2_ROOT"), "catalog-targets.json")))

      target = Enum.find(catalog["models"], &(&1["id"] == "openai/gpt-6-luna"))
      true = target["reasoning"]["mandatory"] == false
      true = "none" in target["reasoning"]["supported_efforts"]

      spec = %{
        base.model
        | id: target["id"],
          capabilities: %{
            tools: %{enabled: true},
            reasoning: %{
              enabled: true,
              effort: %{supported: true, values: target["reasoning"]["supported_efforts"]},
              thinking: %{supported: true, disable_supported: true}
            }
          }
      }

      base |> Map.put(:model, spec) |> Map.put(:reasoning_mode, :none)
    else
      base
    end
  end

  def cases do
    for surface <- [:sync, :stream_text, :stream], kind <- [:text, :tools, :ecto] do
      {"#{kind}_#{surface}", kind, surface}
    end ++
      [
        {"native_sync", :native, :sync},
        {"native_stream", :native, :stream},
        {"empty_ecto_sync", :empty, :sync},
        {"length_sync", :length, :sync},
        {"length_stream", :length, :stream}
      ]
  end

  def tool(counter) do
    ExAgent.Tool.new(
      name: "record_marker",
      description: "Record one synthetic marker and return its receipt.",
      parameters_json_schema: %{
        type: "object",
        properties: %{marker: %{type: "string", enum: ["seven"]}},
        required: ["marker"],
        additionalProperties: false
      },
      takes_ctx: false,
      max_retries: 0,
      call: fn %{"marker" => "seven"} ->
        Agent.update(counter, &(&1 + 1))
        {:ok, "RECEIPT_SEVEN"}
      end
    )
  end

  def execute(agent, prompt, :sync), do: {ExAgent.run(agent, prompt), []}

  def execute(agent, prompt, :stream_text),
    do: {ExAgent.run(agent, prompt, stream_text: true), []}

  def execute(agent, prompt, :stream) do
    events = ExAgent.run_stream(agent, prompt) |> Enum.to_list()
    terminals = Enum.filter(events, fn {tag, _} -> tag in [:result, :error] end)

    result =
      case terminals do
        [{:result, r}] -> {:ok, r}
        [{:error, e}] -> {:error, e}
        _ -> {:harness_error, :invalid_terminals}
      end

    {result, events}
  end

  def one({name, kind, surface}, model) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    before = Agent.get(G2.Ledger, & &1.count)

    if before + 3 > Agent.get(G2.Ledger, &Map.get(&1, :max_count, 30)),
      do: raise("insufficient remaining request reservation")

    common = [
      model: model,
      capabilities:
        if(System.get_env("G2_BOUNDED_INPUT") == "1",
          do: [G2.Admission, G2.InputBudget],
          else: [G2.Admission]
        ),
      output_retries: 0,
      model_settings: [
        temperature: if(System.get_env("G2_NONE_MODEL") == "1", do: nil, else: 0.0),
        max_tokens: if(kind == :length, do: 16, else: 256)
      ],
      usage_limits: %ExAgent.UsageLimits{request_limit: 3, tool_calls_limit: 1},
      instructions: "Follow the synthetic user instruction exactly. Be concise."
    ]

    {extra, prompt} =
      case kind do
        :text ->
          {[], "Reply with exactly G2_OK and nothing else."}

        :tools ->
          {[tools: [tool(counter)]],
           "Call record_marker exactly once with marker seven. After receiving its tool result, reply with exactly the receipt returned by that tool. Do not call any tool again."}

        :ecto ->
          {[output: G2.Output, output_mode: :tool],
           "Return label accepted and count 7 using final_result."}

        :native ->
          {[output: G2.Output, output_mode: :native],
           "Return the JSON object with label accepted and count 7."}

        :empty ->
          {[output: G2.Empty, output_mode: :tool],
           "Return the empty logical object using final_result. Its arguments field must be an empty object."}

        :length ->
          {[tools: [tool(counter)]],
           "Do not call any tools. Output the integers from 1 through 1000, one per line, without abbreviation or commentary. Continue until all 1000 integers are written."}
      end

    started = System.monotonic_time(:millisecond)
    {result, events} = execute(ExAgent.new(common ++ extra), prompt, surface)
    elapsed = System.monotonic_time(:millisecond) - started
    effects = Agent.get(counter, & &1)
    Agent.stop(counter)
    after_count = Agent.get(G2.Ledger, & &1.count)
    summary = summarize(result)
    checks = check(kind, result, effects)

    checks =
      if surface == :stream do
        terminals = Enum.filter(events, fn {tag, _} -> tag in [:result, :error] end)

        Map.merge(checks, %{
          single_last_terminal:
            length(terminals) == 1 and List.last(events) == List.first(terminals)
        })
      else
        checks
      end

    record = %{
      name: name,
      kind: kind,
      surface: surface,
      time_utc: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed,
      effects: effects,
      admissions: after_count - before,
      cumulative_admissions: after_count,
      conservative_reserved_usd:
        Agent.get(G2.Ledger, &Map.get(&1, :reserved_usd, after_count * 0.025)),
      event_tags: Enum.map(events, fn {tag, _} -> tag end),
      checks: checks,
      accepted: Enum.all?(Map.values(checks)),
      result: summary
    }

    File.write!(path("results.jsonl"), Jason.encode!(record) <> "\n", [:append])

    IO.puts(
      Jason.encode!(
        Map.take(record, [
          :name,
          :checks,
          :accepted,
          :effects,
          :admissions,
          :elapsed_ms,
          :cumulative_admissions
        ])
      )
    )

    record
  end

  def summarize({status, r}) when status in [:ok, :error] do
    reason = if status == :error, do: inspect(r.reason, limit: 30)
    r = if status == :error, do: r.partial, else: r
    messages = Map.get(r, :messages, [])
    responses = Enum.filter(messages, &match?(%Response{}, &1))

    %{
      status: status,
      output: if(status == :ok, do: output(r.output)),
      reason: reason,
      request_count: Map.get(r, :request_count),
      tool_calls: Map.get(r, :tool_calls),
      usage: r.usage |> Map.from_struct(),
      responses:
        Enum.map(responses, fn response ->
          %{
            finish_reason: response.finish_reason,
            model_name: response.model_name,
            text: Response.text(response),
            calls: Enum.map(Response.tool_calls(response), &Map.from_struct/1),
            usage: Map.from_struct(response.usage),
            continuation: response.continuation
          }
        end),
      messages_json: Message.to_json(messages)
    }
  end

  def summarize(other), do: %{status: "harness_error", reason: inspect(other)}
  def output(%{__struct__: _} = output), do: Map.from_struct(output)
  def output(output), do: output

  def check(:length, {:error, error}, effects) do
    %{
      incomplete_length:
        match?({:incomplete_response, :length}, error.reason) or
          match?(
            {:model_request_failed, %{reason: {:incomplete_response, :length}}},
            error.reason
          ),
      zero_effects: effects == 0
    }
  end

  def check(kind, {:ok, result}, effects) when kind != :length do
    responses = Enum.filter(result.messages, &match?(%Response{}, &1))
    calls = Enum.flat_map(responses, &Response.tool_calls/1)

    common = %{
      normalized_usage: result.usage.accounting["quality"] == "normalized",
      usage_positive: result.usage.input_tokens > 0 and result.usage.output_tokens > 0,
      message_roundtrip:
        Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages},
      valid_finish: Enum.all?(responses, &(&1.finish_reason in [:stop, :tool_calls]))
    }

    common =
      if System.get_env("G2_NONE_MODEL") == "1" do
        Map.merge(common, %{
          continuation_none_v3:
            Enum.all?(
              responses,
              &(&1.continuation["version"] == 3 and &1.continuation["reasoning_mode"] == "none")
            ),
          no_reasoning_continuation:
            Enum.all?(responses, &(&1.continuation["reasoning_details"] == []))
        })
      else
        common
      end

    specific =
      case kind do
        :text ->
          %{
            output_exact: String.trim(result.output) == "G2_OK",
            one_request: result.request_count == 1,
            zero_effects: effects == 0
          }

        :tools ->
          returns =
            result.messages
            |> Enum.flat_map(& &1.parts)
            |> Enum.filter(&match?(%Part.ToolReturn{}, &1))

          %{
            receipt_exact: String.trim(result.output) == "RECEIPT_SEVEN",
            one_effect: effects == 1,
            two_requests: result.request_count == 2,
            one_host_tool: result.tool_calls == 1,
            logical_args: match?([%Part.ToolCall{args: %{"marker" => "seven"}}], calls),
            codec: Enum.all?(calls, &(&1.metadata["arguments_codec"] == "exagent.arguments/1")),
            id_continuity:
              length(calls) == 1 and length(returns) == 1 and
                hd(calls).tool_call_id == hd(returns).tool_call_id
          }

        :ecto ->
          %{
            ecto_exact: match?(%G2.Output{label: "accepted", count: 7}, result.output),
            logical_args:
              match?([%Part.ToolCall{args: %{"label" => "accepted", "count" => 7}}], calls),
            one_request: result.request_count == 1,
            zero_effects: effects == 0
          }

        :native ->
          %{
            ecto_exact: match?(%G2.Output{label: "accepted", count: 7}, result.output),
            no_tool_calls: calls == [],
            one_request: result.request_count == 1,
            zero_effects: effects == 0
          }

        :empty ->
          %{
            empty_output: match?(%G2.Empty{}, result.output),
            empty_logical_args: length(calls) == 1 and hd(calls).args == %{},
            zero_effects: effects == 0
          }
      end

    Map.merge(common, specific)
  end

  def check(_, _, effects), do: %{expected_result: false, zero_effects: effects == 0}

  def main do
    if System.get_env("G2_LIVE_AUTHORIZED") != "1", do: raise("live authorization required")
    key = System.fetch_env!("OPENROUTER_API_KEY")
    true = byte_size(key) > 0

    existing =
      if File.exists?(path("admissions.json")),
        do: Jason.decode!(File.read!(path("admissions.json")))["count"],
        else: 0

    {:ok, _} = Agent.start_link(fn -> %{count: existing} end, name: G2.Ledger)

    IO.puts(
      Jason.encode!(%{
        elixir: System.version(),
        otp: :erlang.system_info(:otp_release) |> to_string(),
        schedulers: :erlang.system_info(:schedulers_online),
        req_llm: Application.spec(:req_llm, :vsn) |> to_string()
      })
    )

    selection = System.argv()
    cases = Enum.filter(cases(), fn {name, _, _} -> name in selection end)
    if cases == [], do: raise("explicit nonempty case selection required")
    records = Enum.map(cases, &one(&1, model(key)))
    if Enum.any?(records, &(not &1.accepted)), do: System.halt(1)
  end
end

unless System.get_env("G2_LOAD_ONLY") == "1", do: G2.main()

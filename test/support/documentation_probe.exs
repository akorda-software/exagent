# Explicit documentation acceptance, using already compiled checkout BEAMs only:
#   EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs
# Run in a disposable VM. No Mix/install, application config writes, external
# models, Repo, MCP process or network exporter. Source blocks are selected by
# exact heading and ordinal; missing/ambiguous selections fail, never skip.
# Provider strings alone become deterministic fixture variables. Application
# callbacks are imported in a trusted prolog. Config/deps/MCP recipes are parsed,
# not executed; their external gates remain separate. Diagnostics fail acceptance.

unless System.get_env("EXAGENT_OFFLINE") == "1", do: raise("set EXAGENT_OFFLINE=1")
{:ok, _} = Application.ensure_all_started(:exagent)

IO.inspect(%{elixir: System.version(), otp: to_string(:erlang.system_info(:otp_release))},
  label: "RUNTIME"
)

for module <- [
      ExAgent,
      ExAgent.Tools,
      ExAgent.OutputSchema,
      ExAgent.Session,
      ExAgent.Observability.OpenTelemetry
    ] do
  Code.ensure_loaded!(module)

  IO.puts(
    "BEAM #{inspect(module)} #{:code.which(module)} md5=#{Base.encode16(module.module_info(:md5), case: :lower)}"
  )
end

ExUnit.start(seed: 0, timeout: 15_000)

defmodule DocumentationProbe do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test, as: TestModel
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  @root Path.expand("../..", __DIR__)

  defmodule Callbacks do
    def deliver_validated_output(output), do: {:delivered, output}
    def record_failure(reason, partial), do: {:recorded, reason, partial}
  end

  # A native processor with an in-memory mailbox sink. This is an SDK fixture,
  # not BoundedProcessor/OTLP acceptance and not a replacement tracing API.
  defmodule SpanSink do
    def on_start(_context, span, _owner), do: span

    def on_end(span, owner) do
      send(owner, {:documentation_span, span})
      true
    end

    def force_flush(_owner), do: :ok
  end

  test "README one-shot and streaming consume the actual selected codeblocks" do
    block = block("README.md", "## Layer 0 — the one-shot loop")
    {{:ok, %{output: "a test response"} = result}, bindings, warnings} = evaluate(block)
    assert result.status == :succeeded
    assert result.request_count == 1
    assert result.usage.input_tokens == 1
    assert result.usage.output_tokens == 1
    assert Keyword.fetch!(bindings, :text) == result.output
    clean!(warnings)

    streaming = block("README.md", "### Streaming")
    owner = self()

    model = %TestModel{
      script: [
        fn _, _ ->
          send(owner, :stream_request)
          "one two three four five"
        end
      ]
    }

    agent = ExAgent.new(model: model)

    output =
      capture_io(fn ->
        {:ok, _, diagnostics} = evaluate(streaming, agent: agent)
        clean!(diagnostics)
      end)

    assert output =~ "one two three four five\n1 tokens"
    assert_receive :stream_request
    refute_receive :stream_request
  end

  test "README deftool preserves city/days schema and executes valid input" do
    snippet = block("README.md", "### Tools with derived schemas")
    snippet = replace!(snippet, ~s("openai:gpt-4o"), "fixture_model")

    model = %TestModel{
      script: [{:tool_calls, [call("get_weather", %{"city" => "Madrid", "days" => 2})]}, "done"]
    }

    {agent, _, warnings} = evaluate(snippet, fixture_model: model)
    [tool] = agent.tools
    schema = tool.parameters_json_schema |> Jason.encode!() |> Jason.decode!()
    assert schema["required"] == ["city", "days"]
    assert schema["properties"]["city"]["type"] == "string"
    assert schema["properties"]["days"]["type"] == "integer"
    assert tool.takes_ctx
    assert {:ok, result} = ExAgent.run(agent, "weather")
    assert result.output == "done"
    assert result.model.index == 2

    assert [%Part.ToolReturn{status: :succeeded, content: "Madrid: sunny for 2 day(s)"}] =
             returns(result)

    clean!(warnings)
  end

  test "README Ecto block compiles in a fresh context and validates its real schema" do
    snippet = block("README.md", "### Structured output")
    snippet = replace!(snippet, ~s("anthropic:claude-3-5-haiku"), "fixture_model")
    owner = self()

    model = %TestModel{
      script: [
        fn _, params ->
          send(owner, {:output_schema, params.output_tools})

          {:tool_calls,
           [call("final_result", %{"city" => "Madrid", "temp_c" => 22, "condition" => "sunny"})]}
        end
      ]
    }

    {{:ok, result}, bindings, warnings} = evaluate(snippet, fixture_model: model)
    assert result.output.__struct__ == WeatherReport

    assert Map.take(result.output, [:city, :temp_c, :condition]) == %{
             city: "Madrid",
             temp_c: 22.0,
             condition: :sunny
           }

    assert result.model.index == 1
    assert_receive {:output_schema, [_]}
    schema = ExAgent.OutputSchema.json_schema(WeatherReport)
    assert Enum.sort(schema.required) == ["city", "temp_c"]

    assert schema.properties["temp_c"] == %{
             type: "number",
             exclusiveMinimum: -100,
             exclusiveMaximum: 100
           }

    assert {:error, _} =
             ExAgent.OutputSchema.validate(WeatherReport, %{"city" => "Madrid", "temp_c" => 100})

    retry = %TestModel{
      script: [
        {:tool_calls, [call("final_result", %{"city" => "Madrid", "temp_c" => 100})]},
        {:tool_calls,
         [call("final_result", %{"city" => "Madrid", "temp_c" => 22, "condition" => "sunny"})]}
      ]
    }

    assert {:ok, corrected} =
             ExAgent.run(%{Keyword.fetch!(bindings, :agent) | model: retry}, "weather")

    assert corrected.output.temp_c == 22.0
    assert corrected.model.index == 2
    clean!(warnings)
  end

  test "README Session and Coordination blocks preserve turns, handoff and inclusive usage" do
    snippet = block("README.md", "## Layer 3 — multi-agent sessions")
    {{:ok, world, "fighter"}, bindings, warnings} = evaluate(snippet)
    game = Keyword.fetch!(bindings, :game)

    try do
      assert world == %{log: ["rogue acts"]}
      assert ExAgent.Session.read_state(game) == world
      clean!(warnings)
      coordination = block("README.md", "## Coordination")
      coordination = replace!(coordination, ~s("openai:gpt-4o-mini"), "helper_model")
      coordination = replace!(coordination, ~s("openai:gpt-4o"), "parent_model")

      parent_model = %TestModel{
        script: [{:tool_calls, [call("summarize", %{"prompt" => "subtask"})]}, "parent done"]
      }

      {{:ok, "fighter"}, next_bindings, diagnostics} =
        evaluate(coordination,
          game: game,
          helper_model: %TestModel{label: "summary"},
          parent_model: parent_model
        )

      parent = Keyword.fetch!(next_bindings, :parent)
      assert {:ok, result} = ExAgent.run(parent, "delegate")
      assert result.output == "parent done"
      assert result.request_count == 3
      assert result.usage.input_tokens == 3
      assert result.usage.output_tokens == 3
      assert [%Part.ToolReturn{status: :succeeded, content: "summary"}] = returns(result)
      assert {:ok, ^world, "rogue"} = ExAgent.Session.take_turn(game, "fighter", &{:ok, &1})
      clean!(diagnostics)
    after
      GenServer.stop(game)
    end
  end

  test "MIGRATION failure handling executes both branches with trusted callback placeholders" do
    snippet = block("docs/guides/migration.md", "## 1. Run failures retain progress")

    snippet = %{
      snippet
      | code: "import DocumentationProbe.Callbacks\n" <> snippet.code,
        line: snippet.line - 1
    }

    agent = ExAgent.new(model: %TestModel{label: "validated"})
    {{:delivered, "validated"}, _, warnings} = evaluate(snippet, agent: agent, prompt: "go")
    clean!(warnings)
    effects = :atomics.new(1, [])

    tool =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{type: "object"},
        call: fn _ctx, _args ->
          :atomics.add(effects, 1, 1)
          "saved"
        end
      )

    model = %TestModel{
      script: [{:tool_calls, [call("effect")]}, fn _, _ -> raise "fixture model failure" end]
    }

    agent = ExAgent.new(model: model, tools: [tool])

    {{:recorded, {:model_request_failed, %RuntimeError{message: "fixture model failure"}},
      partial}, _, diagnostics} =
      evaluate(snippet, agent: agent, prompt: "go")

    assert partial.status == :failed
    assert partial.output == nil
    assert partial.model.index == 1
    assert partial.usage.input_tokens == 1
    assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(partial)
    assert :atomics.get(effects, 1) == 1
    clean!(diagnostics)
  end

  test "opt-in tracing snippets run with TestModel and content redaction reaches native spans" do
    # Literal construction/run first: API-only no-op, no SDK startup/configuration.
    model = %TestModel{label: "fixture output"}
    snippet = block("README.md", "## OpenTelemetry")
    {agent, _, warnings} = evaluate(snippet, model: model)
    assert agent.observability.content == false
    assert {:ok, %{output: "fixture output"}} = ExAgent.run(agent, "fixture prompt")
    clean!(warnings)

    snippet = block("docs/guides/observability.md", "## 2. Enable instrumentation")
    {{:ok, result}, _, diagnostics} = evaluate(snippet, model: model)
    assert result.output == "fixture output"
    clean!(diagnostics)

    # A named SDK provider in this disposable VM, without replacing the global
    # provider or changing application env. Private SDK bootstrap is fixture-only
    # for SDK 1.7; package/config acceptance lives in package_acceptance fixtures.
    global = :opentelemetry.get_tracer()

    :ok =
      :otel_span_limits.set(%{
        attribute_count_limit: 128,
        attribute_value_length_limit: :infinity,
        event_count_limit: 128,
        link_count_limit: 128,
        attribute_per_event_limit: 128,
        attribute_per_link_limit: 128
      })

    {:ok, storage} = :otel_span_ets.start_link([])
    {:ok, supervisor} = :otel_tracer_provider_sup.start_link()
    resource = :otel_resource.create(%{"service.name" => "documentation-probe"})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{SpanSink, self()}]
    }

    {:ok, _} = :otel_tracer_provider_sup.start(:documentation_probe, resource, config)

    try do
      tracer = :otel_tracer_provider.get_tracer(:documentation_probe, :exagent, "1", :undefined)
      # Positive native control distinguishes an incomplete SDK fixture from a
      # documentation/instrumentation failure (the adapter is fail-open).
      native = :otel_tracer.start_span(%{}, tracer, "fixture control", %{})
      assert :otel_span.is_recording(native)
      :otel_span.end_span(native)
      assert length(collect_spans(1)) == 1

      assert {:ok, %{output: "fixture output"}} =
               ExAgent.run(
                 %{agent | observability: %{agent.observability | tracer: tracer}},
                 "fixture prompt"
               )

      off = collect_spans(2)

      refute inspect(Enum.map(off, &:otel_attributes.map(span(&1, :attributes)))) =~
               "fixture prompt"

      refute inspect(Enum.map(off, &:otel_attributes.map(span(&1, :attributes)))) =~
               "fixture output"

      redaction = block("docs/guides/observability.md", "## 3. Privacy before export")

      {tracing, _, diagnostics} =
        evaluate(redaction, [], "alias ExAgent.Observability.OpenTelemetry\n")

      assert tracing.content
      agent = ExAgent.new(model: model, observability: %{tracing | tracer: tracer})
      assert {:ok, %{output: "fixture output"}} = ExAgent.run(agent, "fixture prompt")
      spans = collect_spans(2)
      assert Enum.all?(spans, &(span(&1, :span_id) > 0))
      attrs = Enum.map(spans, &:otel_attributes.map(span(&1, :attributes)))
      assert Enum.any?(attrs, &("[content withheld]" in Map.values(&1)))
      refute inspect(attrs) =~ "fixture prompt"
      refute inspect(attrs) =~ "fixture output"
      clean!(diagnostics)

      context = block("docs/guides/observability.md", "## 2. Enable instrumentation", 2)
      parent = :otel_tracer.start_span(%{}, tracer, "fixture parent", %{})
      token = :otel_ctx.attach(:otel_tracer.set_current_span(%{}, parent))

      {task, _, diagnostics} =
        evaluate(context, [agent: agent], "alias ExAgent.Observability.OpenTelemetry\n")

      assert {:ok, %{output: "fixture output"}} = Task.await(task)
      assert :otel_tracer.current_span_ctx() == parent
      :otel_ctx.detach(token)
      :otel_span.end_span(parent)
      propagated = collect_spans(3)
      assert Enum.all?(propagated, &(span(&1, :trace_id) == :otel_span.trace_id(parent)))
      [run] = Enum.filter(propagated, &(span(&1, :name) == "exagent.run"))
      assert span(run, :parent_span_id) == :otel_span.span_id(parent)
      assert :otel_tracer.current_span_ctx() == :undefined
      assert :opentelemetry.get_tracer() == global
      clean!(diagnostics)
    after
      Supervisor.stop(supervisor)
      GenServer.stop(storage)
    end
  end

  test "external setup recipes have explicit syntax-only gates, never execute their side effects" do
    recipes = [
      {"README.md", "## Quick start", 1, "Mix.install: package consumer gate"},
      {"README.md", "## Layer 2 — snapshots & resume", 2, "Postgres: authorized Repo/DB gate"},
      {"README.md", "## External tools (MCP)", 1, "npx/MCP: separate authorized backend gate"},
      {"docs/guides/observability.md", "## 1. Application setup", 2,
       "runtime Config/native OTLP: N01-N04 plus external endpoint gate"}
    ]

    for {file, heading, ordinal, gate} <- recipes do
      snippet = block(file, heading, ordinal)

      assert {:ok, _} =
               Code.string_to_quoted(snippet.code, file: snippet.file, line: snippet.line)

      IO.puts("SYNTAX ONLY #{snippet.file}:#{snippet.line}: #{gate}")
    end

    # A dependency-list fragment is intentionally not a standalone Elixir form.
    deps = block("docs/guides/observability.md", "## 1. Application setup")

    assert {:ok, _} =
             Code.string_to_quoted("[\n" <> deps.code <> "]",
               file: deps.file,
               line: deps.line - 1
             )

    IO.puts("SYNTAX ONLY #{deps.file}:#{deps.line}: list-fragment prolog; package graph gate")
  end

  defp block(file, heading, ordinal \\ 1) do
    source = File.read!(Path.join(@root, file))
    [prefix, following] = String.split(source, heading <> "\n")
    section = following |> String.split(~r/^\#{2,3} /m, parts: 2) |> hd()
    matches = Regex.scan(~r/^```elixir\n(.*?)^```/ms, section, return: :index)
    [_, {offset, length}] = Enum.fetch!(matches, ordinal - 1)
    code = binary_part(section, offset, length)
    assert String.trim(code) != ""

    line =
      length(String.split(prefix <> heading <> "\n" <> binary_part(section, 0, offset), "\n"))

    hash = :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
    IO.puts("SELECT #{file}:#{line} block=#{ordinal} sha256=#{hash}")
    %{code: code, file: file, line: line}
  end

  defp replace!(snippet, literal, fixture) do
    [_before, _after] = String.split(snippet.code, literal)
    IO.puts("FIXTURE #{snippet.file}:#{snippet.line}: #{literal} => #{fixture}")
    %{snippet | code: String.replace(snippet.code, literal, fixture)}
  end

  defp evaluate(snippet, bindings \\ [], prolog \\ "") do
    {outcome, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          {:ok,
           Code.eval_string(prolog <> snippet.code, bindings,
             file: snippet.file,
             line: snippet.line - (length(String.split(prolog, "\n")) - 1)
           )}
        rescue
          error -> {:error, error, __STACKTRACE__}
        end
      end)

    if diagnostics != [], do: IO.inspect(diagnostics, label: "DOC DIAGNOSTICS", limit: :infinity)

    case outcome do
      {:ok, {value, bindings}} -> {value, bindings, diagnostics}
      {:error, error, stack} -> reraise error, stack
    end
  end

  defp clean!(diagnostics),
    do: assert(diagnostics == [], "documentation diagnostics: #{inspect(diagnostics)}")

  defp call(name, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, args: args, tool_call_id: name}

  defp returns(result),
    do:
      for(
        message <- result.messages,
        part <- message.parts,
        match?(%Part.ToolReturn{}, part),
        do: part
      )

  defp collect_spans(0), do: []

  defp collect_spans(left) do
    receive do
      {:documentation_span, record} -> [record | collect_spans(left - 1)]
    after
      1000 -> flunk("missing #{left} native spans")
    end
  end
end

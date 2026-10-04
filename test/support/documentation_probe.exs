# Explicit documentation acceptance, using already compiled checkout BEAMs only:
#   EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs
# Run in a disposable VM. No Mix/install, host config writes, external
# models, Repo, MCP process or network exporter. Source blocks are selected by
# exact heading and ordinal; missing/ambiguous selections fail, never skip.
# Provider strings alone become deterministic fixture variables. Application
# callbacks are imported in a trusted prolog. Config/deps/MCP recipes are parsed,
# not executed; their external gates remain separate. Diagnostics fail acceptance.

unless System.get_env("EXAGENT_OFFLINE") == "1", do: raise("set EXAGENT_OFFLINE=1")
# Plain elixir does not load config/test.exs. Keep the disposable VM off .env.
Application.put_env(:req_llm, :load_dotenv, false)
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
  Code.require_file(Path.join(@root, "docs/markdown_formatter.exs"))

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

  test "Markdown formatter rebases navigation while preserving literal code and external URLs" do
    source = Path.join(@root, "docs/guides/agents.md")

    sources = %{
      Path.join(@root, "docs/status.md") => "status.md",
      Path.join(@root, "docs/README.md") => "documentation.md"
    }

    input = """
    [Status](../status.md#support) and [`map`](../README.md).
    [`map`]: ../README.md
    <a href="ExAgent.html#run/3">API</a>
    Literal `[Status](../status.md)` stays intact.
    [External](https://example.invalid/../status.md) and [here](#support).
    ```elixir
    "[Status](../status.md)"
    ```
    ~~~~text
    [Status](../status.md)
    ~~~~
    """

    output = ExAgent.Docs.Markdown.rebase(input, source, sources, MapSet.new(["ExAgent.html"]))
    assert output =~ "[Status](status.md#support) and [`map`](documentation.md)."
    assert output =~ "[`map`]: documentation.md"
    assert output =~ ~s(<a href="ExAgent.md#run/3">API</a>)
    assert output =~ "Literal `[Status](../status.md)` stays intact."
    assert output =~ "[External](https://example.invalid/../status.md) and [here](#support)."
    assert output =~ "```elixir\n\"[Status](../status.md)\"\n```"
    assert output =~ "~~~~text\n[Status](../status.md)\n~~~~"
  end

  test "welcome and getting-started preserve results and stateful model progress" do
    {"a test response", _, diagnostics} =
      evaluate(block("docs/home.md", "## A small, working beginning"))

    clean!(diagnostics)

    {%{output: "a test response", status: :succeeded, requests: 1}, bindings, diagnostics} =
      evaluate(block("docs/guides/getting-started.md", "## Run your first agent"))

    clean!(diagnostics)
    agent = Keyword.fetch!(bindings, :agent)

    {"second", bindings, diagnostics} =
      evaluate(block("docs/guides/getting-started.md", "## Keep a conversation"),
        agent: %{agent | model: %TestModel{script: ["first", "second"]}}
      )

    assert Keyword.fetch!(bindings, :second).model.index == 2
    clean!(diagnostics)

    {{:completed, "a test response"}, _, diagnostics} =
      evaluate(block("docs/guides/getting-started.md", "## Handle success and failure"),
        agent: agent
      )

    clean!(diagnostics)
  end

  test "task-guide tool and output examples execute the actual derived schemas" do
    {[_tool], _, diagnostics} =
      evaluate(block("docs/guides/tools-and-output.md", "## Define a tool"))

    clean!(diagnostics)

    {%{output: "3 kilometres is 3000 metres.", requests: 2, tools: 1}, bindings, diagnostics} =
      evaluate(block("docs/guides/tools-and-output.md", "## Exercise the whole tool loop"))

    assert [%Part.ToolReturn{status: :succeeded, content: 3000}] =
             returns(Keyword.fetch!(bindings, :result))

    clean!(diagnostics)

    {3000, bindings, diagnostics} =
      evaluate(block("docs/guides/tools-and-output.md", "## Return an Ecto struct"))

    assert Keyword.fetch!(bindings, :result).output.__struct__ == DocumentationDistance
    clean!(diagnostics)
  end

  test "model guide resolves configuration without requests and bounds the local run" do
    for heading <- ["## Resolve a text model", "## Configure Chat tools and streaming"] do
      snippet = block("docs/guides/models-and-limits.md", heading)

      snippet =
        replace!(snippet, ~s|System.fetch_env!("OPENAI_API_KEY")|, ~s("synthetic-doc-key"))

      {_, bindings, diagnostics} = evaluate(snippet)
      model = Keyword.fetch!(bindings, :model)
      assert ExAgent.Model.model_name(model) == "gpt-4o-mini"

      if heading == "## Configure Chat tools and streaming",
        do: assert(model.tool_profile == :chat_tools_v1)

      clean!(diagnostics)
    end

    {1, bindings, diagnostics} =
      evaluate(block("docs/guides/models-and-limits.md", "## Bound requests and tool calls"))

    assert Keyword.fetch!(bindings, :agent).usage_limits.request_limit == 3
    clean!(diagnostics)
  end

  test "runtime guide subscribes before admission and consumes a terminal stream once" do
    {%{first: "a test response", second: "a test response"}, bindings, diagnostics} =
      evaluate(block("docs/guides/runtime-and-events.md", "## Start a conversation"))

    clean!(diagnostics)
    server = Keyword.fetch!(bindings, :server)

    try do
      {"a test response", _, diagnostics} =
        evaluate(
          block(
            "docs/guides/runtime-and-events.md",
            "## Subscribe before asynchronous admission"
          ),
          server: server
        )

      clean!(diagnostics)
    after
      ExAgent.AgentSupervisor.stop_agent(server)
    end

    {"Hello from Elixir", bindings, diagnostics} =
      evaluate(block("docs/guides/runtime-and-events.md", "## Stream a one-shot run"))

    assert Enum.count(Keyword.fetch!(bindings, :events), &match?({:result, _}, &1)) == 1
    clean!(diagnostics)
  end

  test "checkpoint guide confirms data under the documented namespace" do
    {"a test response", bindings, diagnostics} =
      evaluate(
        block("docs/guides/durability-and-approvals.md", "## Add a conversation checkpoint")
      )

    server = Keyword.fetch!(bindings, :server)
    store = ExAgent.Store.scoped(:ets, "docs-workspace")

    try do
      assert {:ok, _} = ExAgent.Store.load_agent_snapshot(store, "docs-checkpoint")
      clean!(diagnostics)
    after
      ExAgent.AgentSupervisor.stop_agent(server)
      ExAgent.Store.delete_agent_snapshot(store, "docs-checkpoint")
    end
  end

  test "coordination guide delegates in scope and passes the shared-state turn" do
    {"Summary received.", bindings, diagnostics} =
      evaluate(block("docs/guides/coordination.md", "## Delegate inside the parent's scope"))

    result = Keyword.fetch!(bindings, :result)
    assert [%Part.ToolReturn{status: :succeeded, content: "A concise summary."}] = returns(result)
    assert result.usage.input_tokens == 3
    clean!(diagnostics)

    {["Draft ready"], bindings, diagnostics} =
      evaluate(block("docs/guides/coordination.md", "## Give shared state one writer"))

    session = Keyword.fetch!(bindings, :session)

    try do
      assert %{notes: ["Draft ready"]} = ExAgent.Session.read_state(session)
      clean!(diagnostics)
    after
      GenServer.stop(session)
    end
  end

  test "testing guide executes its actual ExUnit example assertions" do
    {_, _, diagnostics} =
      evaluate(block("docs/guides/testing.md", "## Assert on the public result"))

    clean!(diagnostics)
    assert Code.ensure_loaded?(DocumentationAgentTest)
    apply(DocumentationAgentTest, :"test returns the validated final output", [%{}])
  end

  test "testing guide preserves one effect and failed progress when a script is exhausted" do
    {%{status: :failed, requests: 2, effects: 1}, bindings, diagnostics} =
      evaluate(block("docs/guides/testing.md", "## Script every expected request"))

    assert [%Part.ToolReturn{status: :succeeded, content: "recorded"}] =
             returns(Keyword.fetch!(bindings, :partial))

    clean!(diagnostics)
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
    snippet = block("README.md", "### Define a tool")

    model = %TestModel{
      script: [{:tool_calls, [call("get_weather", %{"city" => "Madrid", "days" => 2})]}, "done"]
    }

    {agent, _, warnings} = evaluate(snippet, chat_model: model)
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

  test "runtime recipe scopes public events and supports idempotent cancellation" do
    recipe = block("docs/guides/migration.md", "### Minimal runtime integration recipe")
    agent = ExAgent.new(model: %TestModel{label: "hello"})
    {handles, _, warnings} = evaluate(recipe, agent: agent)
    clean!(warnings)
    %{server: server, namespace: namespace, request_id: request_id, cancel: cancel} = handles

    assert_receive {:exagent_event,
                    %ExAgent.Event{
                      namespace: ^namespace,
                      request_id: ^request_id,
                      type: :run_finished,
                      payload: %{output: "hello"}
                    }},
                   1000

    assert :ok = cancel.()
    assert %{pending: 0, pending_bytes: 0, namespace: ^namespace} = ExAgent.Server.health(server)
    GenServer.stop(server)

    :ok =
      ExAgent.Store.delete_agent_snapshot(ExAgent.Store.scoped(:ets, namespace), "conversation-1")
  end

  test "README explicit Chat constructor resolves and admits the documented profile without IO" do
    snippet = block("README.md", "### Tools with derived schemas")
    snippet = replace!(snippet, ~s|System.fetch_env!("OPENAI_API_KEY")|, ~s("synthetic-doc-key"))
    {model, _, diagnostics} = evaluate(snippet)
    assert %ExAgent.Models.ReqLLM{tool_profile: :chat_tools_v1} = model
    assert ExAgent.Model.model_name(model) == "gpt-4o-mini"
    assert ExAgent.Model.profile(model).supports_tools
    assert {:ok, ^model} = ExAgent.Model.resolve(model)
    clean!(diagnostics)
  end

  test "README Ecto block compiles in a fresh context and validates its real schema" do
    snippet = block("README.md", "### Structured output")
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

    {{:ok, result}, bindings, warnings} = evaluate(snippet, chat_model: model)
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

      coordination =
        replace!(
          coordination,
          "helper = ExAgent.new(model: chat_model",
          "helper = ExAgent.new(model: helper_model"
        )

      coordination = replace!(coordination, "model: chat_model", "model: parent_model")

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

  test "Opik guide projection preserves native identity, scalars, privacy and finite expansion" do
    {_, _, diagnostics} =
      evaluate(block("docs/guides/observability.md", "### Opik attribute presentation"))

    clean!(diagnostics)

    fixture =
      @root
      |> Path.join("test/support/langfuse_acceptance/opik_profile_control.exs")
      |> File.read!()
      |> String.replace(
        ~s|Code.require_file(Path.expand("opik_profile.exs", __DIR__))|,
        ""
      )
      |> String.replace("alias OpikAcceptance.Profile", "alias MyApp.OpikProjection, as: Profile")

    capture_io(fn ->
      Code.eval_string(fixture)
    end)
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

      integration =
        block("docs/guides/observability.md", "### ReqLLM and one owner for request spans")

      {:ok, _, diagnostics} = evaluate(integration)
      clean!(diagnostics)

      context = block("docs/guides/observability.md", "### Application-owned process boundaries")
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
      ExAgent.Observability.ReqLLM.detach()
      Supervisor.stop(supervisor)
      GenServer.stop(storage)
    end
  end

  test "external setup recipes have explicit syntax-only gates, never execute their side effects" do
    recipes = [
      {"docs/guides/mcp.md", "## Connect a stdio server", 1, "external stdio: MCP SDK gate"},
      {"docs/guides/mcp.md", "## Supply an HTTP pool", 1, "Finch child: host supervision gate"},
      {"docs/guides/mcp.md", "## Supply an HTTP pool", 2, "external HTTP: MCP SDK gate"},
      {"docs/guides/getting-started.md", "## Install ExAgent 2.0", 1,
       "deps: package consumer gate"},
      {"docs/guides/getting-started.md", "## Install ExAgent 2.0", 2,
       "Config: host startup gate"},
      {"README.md", "## Quick start", 1, "Mix.install: package consumer gate"},
      {"README.md", "## Quick start", 2, "stock tuple with explicit auth: resolution TCP gate"},
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

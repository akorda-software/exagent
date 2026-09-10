defmodule ExAgent.Observability.OpenTelemetry do
  @moduledoc """
  Optional native OpenTelemetry instrumentation, using the application's tracer.

      tracing = ExAgent.Observability.OpenTelemetry.new()
      agent = ExAgent.new(model: model, observability: tracing)

  Add `:opentelemetry_api`, an SDK and an exporter in the host application and
  configure `ExAgent.Observability.BoundedProcessor` for finite admission and
  observable drops/export failures (see `docs/guides/observability.md`). The native SDK's
  batch processor has a soft queue threshold rather than that hard bound. This
  module never starts or replaces a tracer provider, configures an exporter, or
  performs network IO. `:tracer` may be an application-supplied native tracer;
  otherwise the instrumentation scope is `:exagent`, version `"1"`.

  The small `exagent.gen_ai.v1` profile uses `gen_ai.usage.*` on model requests
  only. Run totals use `exagent.usage.*` and are inclusive of descendants; do not
  sum them with generation usage. Costs are estimates in cents from the existing
  execution ledger, not a second pricing callback or an authoritative bill.
  The profile is pinned to GenAI commit
  `b5d8440f6f126738fd50f927752cd669772c517b`; no schema URL is invented. Native
  Anthropic input is cache-exclusive and is normalized only for generation
  `gen_ai.usage.input_tokens`; OpenAI-compatible built-ins already report an
  inclusive total. Custom model semantics are unknown: their input remains in
  `exagent.usage.reported_input_tokens` instead of claiming a GenAI total. Run
  aggregates retain the existing ledger's provider-native token semantics.
  A Server terminal synthesized after abort/worker loss has only its last
  progress snapshot: `exagent.usage.source=last_progress`, partial usage and an
  unknown total cost. Observed token/count subtotals are retained, and any known
  monetary subtotal uses `exagent.cost.known_subtotal_cents` instead of claiming
  a complete `exagent.cost.cents`. Normal core results keep their reported status.

  Content is off by default. Opting in requires both `content: true` and
  `redact: fn field, value -> {:ok, safe_binary} | :drop end`. The callback sees
  only explicitly selected prompt/output/messages/tool arguments/results, never
  model structs, dependencies, configuration, exceptions or hidden reasoning.
  Content is admitted only after successful redaction, valid UTF-8 and byte-limit
  checks. Invalid/raising callbacks and oversized values drop the entire field.
  Opaque values and structs are dropped; redaction input is bounded plain data.
  No prefixes of unredacted content are exported. Redactors are trusted local
  callbacks and should be fast; they are not sandboxed.

  `max_content_bytes` defaults to 4096 per field (at most two fields per span).
  `max_content_input_bytes` defaults to 65536; oversized inputs are not sent to
  the redactor. Labels/IDs are bounded to 256 bytes. Use non-secret identifiers
  for agent, tool, model and correlation names. Arbitrary metadata, baggage,
  provider bodies, exception messages and stacktraces are never attributes.

  `capture_context/0` and `with_context/2` propagate only span context and this
  configuration across application-owned tasks. These handles are ephemeral,
  not snapshot/JSON data. Server queues capture context at admission; a public
  lazy stream captures it at enumeration, unless `trace_context:` is supplied.
  Every attachment restores both prior OTel context and Logger metadata.

  Native SDK span storage provides idempotent completion. A monitor per recording
  operation also closes its span when the executing process dies (including
  `:kill`), without another tracing registry or export queue. Hard termination
  cannot recover unreported usage and is marked partial. SDK shutdown or VM death
  can lose spans. Arbitrary synchronous processors/samplers installed by the host
  can block instrumentation; use the bounded batch setup in the example.

  Instrumentation failures emit `[:exagent, :observability, :failure]` with a
  numeric count and a fixed stage. Redaction drops emit
  `[:exagent, :observability, :content_dropped]`, without content or raw errors.
  """

  alias ExAgent.Message.{Part, Request, Response, Usage}

  defstruct content: false,
            redact: nil,
            max_content_bytes: 4096,
            max_content_input_bytes: 65_536,
            tracer: nil

  @type t :: %__MODULE__{}
  @key {__MODULE__, :configuration}
  @logger_keys [:otel_trace_id, :otel_span_id, :otel_trace_flags]
  @profile "exagent.gen_ai.v1"
  @gen_ai_revision "b5d8440f6f126738fd50f927752cd669772c517b"
  @compile {:no_warn_undefined, [:otel_ctx, :otel_tracer, :otel_span, :opentelemetry]}

  defmodule Context do
    @moduledoc false
    defstruct [:native, :config]
  end

  defmodule Operation do
    @moduledoc false
    defstruct [:span, :context, :watcher, :kind]
  end

  @doc "Build an opt-in instrumentation configuration without changing the SDK."
  def new(opts \\ []) do
    config = struct!(__MODULE__, opts)

    unless is_boolean(config.content) and
             (not config.content or is_function(config.redact, 2)) and
             (is_nil(config.redact) or is_function(config.redact, 2)) and
             is_integer(config.max_content_bytes) and config.max_content_bytes in 1..65_536 and
             is_integer(config.max_content_input_bytes) and
             config.max_content_input_bytes in 1..1_048_576 and
             (is_nil(config.tracer) or is_tuple(config.tracer)) do
      raise ArgumentError, "invalid OpenTelemetry instrumentation options"
    end

    config
  end

  @doc "Capture a runtime-only span context; baggage and arbitrary context values are excluded."
  def capture_context do
    if Code.ensure_loaded?(:otel_ctx) do
      safely(:context, nil, fn ->
        %Context{
          native: :otel_tracer.set_current_span(%{}, :otel_tracer.current_span_ctx()),
          config: Process.get(@key)
        }
      end)
    end
  end

  @doc "Run a function under a captured context, restoring the caller even on exceptions."
  def with_context(nil, fun), do: fun.()

  def with_context(%Context{native: native, config: config}, fun) do
    previous = Process.get(@key)
    logger = :logger.get_process_metadata()
    # Native attach updates metadata but does not remove old IDs when the new
    # context has no span. Clear only our keys before attaching, not just on exit.
    restore_logger(:undefined)
    token = safely(:context, :unavailable, fn -> :otel_ctx.attach(native) end)
    if token == :unavailable, do: restore_logger(logger)
    Process.put(@key, config)

    try do
      fun.()
    after
      if token != :unavailable, do: safely(:context, nil, fn -> :otel_ctx.detach(token) end)
      if previous == nil, do: Process.delete(@key), else: Process.put(@key, previous)

      restore_logger(logger)
    end
  end

  defp restore_logger(previous) do
    current =
      case :logger.get_process_metadata() do
        :undefined -> %{}
        metadata -> metadata
      end

    previous_ids = if is_map(previous), do: Map.take(previous, @logger_keys), else: %{}
    restored = current |> Map.drop(@logger_keys) |> Map.merge(previous_ids)

    if restored == %{} and previous == :undefined,
      do: :logger.unset_process_metadata(),
      else: :logger.set_process_metadata(restored)
  end

  @doc false
  def options(opts), do: Keyword.put_new_lazy(opts, :trace_context, &capture_context/0)

  @doc false
  def configuration(default, opts) do
    fallback = if default == false, do: false, else: default || inherited(opts)

    case Keyword.get(opts, :observability, fallback) do
      %__MODULE__{} = config -> config
      _ -> nil
    end
  end

  defp inherited(opts) do
    case Keyword.get(opts, :trace_context) do
      %Context{config: config} -> config
      _ -> Process.get(@key)
    end
  end

  @doc false
  def start(config, kind, attributes, context \\ nil)
  def start(nil, _kind, _attributes, _context), do: nil

  def start(%__MODULE__{} = config, kind, attributes, context) do
    safely(:start, nil, fn ->
      if Code.ensure_loaded?(:otel_tracer) do
        parent = context || capture_context()
        native = if parent, do: parent.native, else: %{}
        tracer = config.tracer || :opentelemetry.get_tracer(:exagent, "1", :undefined)

        span =
          :otel_tracer.start_span(native, tracer, "exagent." <> Atom.to_string(kind), %{
            kind: if(kind == :model, do: :client, else: :internal),
            attributes: compact(Map.merge(base_attributes(kind), attributes))
          })

        context = %Context{native: :otel_tracer.set_current_span(%{}, span), config: config}
        owner = self()

        watcher =
          if :otel_span.is_recording(span) do
            spawn(fn ->
              ref = Process.monitor(owner)

              receive do
                :finished -> Process.demonitor(ref, [:flush])
                {:DOWN, ^ref, :process, ^owner, _} -> abandoned(span, kind)
              end
            end)
          end

        %Operation{span: span, context: context, watcher: watcher, kind: kind}
      else
        diagnostic(:failure, :api_unavailable)
        nil
      end
    end)
  end

  @doc false
  def context(nil), do: nil
  def context(%Operation{context: context}), do: context

  @doc false
  def within(operation, fun), do: with_context(context(operation), fun)

  @doc false
  def finish(nil, _result), do: :ok

  def finish(%Operation{} = operation, result) do
    safely(:finish, :ok, fn ->
      {status, reason} = outcome(result)
      attributes(operation, %{"exagent.status" => status})
      if reason, do: record_error(operation, reason)
    end)

    safely(:finish, :ok, fn -> end_native(operation.span) end)

    if operation.watcher, do: send(operation.watcher, :finished)
    :ok
  end

  @doc false
  def around(config, kind, attrs, context, fun) do
    operation = start(config, kind, attrs, context)

    within(operation, fn ->
      try do
        result = fun.(operation)
        finish(operation, result)
        result
      catch
        class, reason ->
          finish(
            operation,
            {:error, if(reason == :exagent_stream_cancelled, do: :cancelled, else: reason)}
          )

          :erlang.raise(class, reason, __STACKTRACE__)
      end
    end)
  end

  @doc false
  def attributes(nil, _attrs), do: :ok

  def attributes(operation, attrs),
    do:
      safely(:attributes, :ok, fn -> :otel_span.set_attributes(operation.span, compact(attrs)) end)

  @doc false
  def ids(state) do
    Map.new(
      [
        :run_id,
        :root_run_id,
        :parent_run_id,
        :model_request_id,
        :agent_id,
        :session_id,
        :request_id,
        :tool_call_id
      ],
      fn key ->
        {"exagent." <> Atom.to_string(key), label(Map.get(state, key))}
      end
    )
    |> compact()
  end

  @doc false
  def label(value) when is_binary(value) and byte_size(value) <= 256 do
    if String.valid?(value) and Regex.match?(~r/\A[A-Za-z0-9_.:\/ -]+\z/, value), do: value
  end

  def label(value) when is_atom(value) and not is_nil(value), do: label(Atom.to_string(value))
  def label(_), do: nil

  @doc false
  def run_result(operation, result), do: run_result(operation, result, :confirmed)

  @doc false
  def run_result(nil, _result, _source), do: :ok

  def run_result(operation, {:error, %ExAgent.RunError{partial: result}}, source),
    do: run_result(operation, {:ok, result}, source)

  def run_result(operation, {:error, %ExAgent.CheckpointError{result: result}}, source),
    do: run_result(operation, result, source)

  def run_result(operation, {:ok, result}, source) when is_map(result) do
    attributes(
      operation,
      Map.merge(ids(result), %{
        "exagent.usage.input_tokens" =>
          token(get_in(result, [:usage, Access.key(:input_tokens)])),
        "exagent.usage.output_tokens" =>
          token(get_in(result, [:usage, Access.key(:output_tokens)])),
        "exagent.usage.request_count" => token(result[:request_count]),
        "exagent.usage.tool_calls" => token(result[:tool_calls])
      })
      |> Map.merge(run_accounting_attributes(result, source))
    )

    content(operation, :output, result[:output])
  end

  def run_result(_, _, _), do: :ok

  defp run_accounting_attributes(result, :last_progress) do
    %{
      "exagent.usage.status" => "partial",
      "exagent.usage.source" => "last_progress",
      "exagent.cost.status" => "unknown",
      "exagent.cost.known_subtotal_cents" => number(result[:cost_cents])
    }
  end

  defp run_accounting_attributes(result, :confirmed) do
    %{
      "exagent.usage.status" => label(result[:usage_status]),
      "exagent.cost.cents" => number(result[:cost_cents]),
      "exagent.cost.status" => label(result[:cost_status])
    }
  end

  @doc false
  def model_result(nil, _snapshot, _model), do: :ok

  def model_result(operation, {:ok, snapshot}, model) do
    usage = snapshot.usage
    details = if match?(%Usage{}, usage), do: usage.details, else: %{}

    attributes(operation, %{
      "gen_ai.usage.input_tokens" => input_tokens(usage, model),
      "exagent.usage.reported_input_tokens" => if(usage, do: token(usage.input_tokens)),
      "exagent.usage.input_tokens_semantics" => input_semantics(model),
      "gen_ai.usage.output_tokens" => if(usage, do: token(usage.output_tokens)),
      "gen_ai.usage.cache_read.input_tokens" =>
        detail(details, [:cached_tokens, :cache_read_input_tokens]),
      "gen_ai.usage.cache_write.input_tokens" => detail(details, [:cache_creation_input_tokens]),
      "exagent.usage.reasoning_tokens" => detail(details, [:reasoning_tokens]),
      "exagent.usage.status" => label(snapshot.usage_status),
      "exagent.cost.cents" => number(snapshot.cost_cents),
      "exagent.cost.status" => label(snapshot.cost_status)
    })
  end

  def model_result(_, _, _), do: :ok

  defp input_semantics(%ExAgent.Models.Anthropic{}), do: "exclusive_cache"

  defp input_semantics(%module{})
       when module in [
              ExAgent.Models.OpenAI,
              ExAgent.Models.OpenRouter,
              ExAgent.Models.OpenCode,
              ExAgent.Models.Test
            ],
       do: "inclusive"

  defp input_semantics(_), do: "provider_reported"

  defp input_tokens(%Usage{input_tokens: input, details: details}, model)
       when is_integer(input) do
    case input_semantics(model) do
      "exclusive_cache" ->
        input + (detail(details, [:cache_read_input_tokens]) || 0) +
          (detail(details, [:cache_creation_input_tokens]) || 0)

      "inclusive" ->
        input

      _ ->
        nil
    end
  end

  defp input_tokens(_, _), do: nil

  @doc false
  def model_attributes(nil, _model), do: %{}

  def model_attributes(_config, model) do
    safely(:attributes, %{}, fn ->
      compact(%{
        "gen_ai.request.model" => label(ExAgent.Model.model_name(model)),
        "gen_ai.provider.name" => label(ExAgent.Model.system(model))
      })
    end)
  end

  @doc false
  def content(nil, _field, _value), do: :ok
  def content(%Operation{context: %Context{config: %{content: false}}}, _, _), do: :ok

  def content(%Operation{context: %Context{config: config}} = operation, field, value) do
    try do
      with true <- content_size(value, config.max_content_input_bytes, 0) >= 0,
           {:ok, safe} <- config.redact.(field, value),
           true <-
             is_binary(safe) and byte_size(safe) <= config.max_content_bytes and
               String.valid?(safe) do
        attributes(operation, %{("exagent.content." <> Atom.to_string(field)) => safe})
      else
        _ -> diagnostic(:content_dropped, field)
      end
    rescue
      _ -> diagnostic(:content_dropped, field)
    catch
      _, _ -> diagnostic(:content_dropped, field)
    end
  end

  @doc false
  def messages(nil, _messages), do: :ok
  def messages(%Operation{context: %Context{config: %{content: false}}}, _), do: :ok

  def messages(operation, messages) do
    # Only conversational content, not message/model dumps or thinking/signatures.
    safely(:content_projection, :ok, fn ->
      budget = operation.context.config.max_content_input_bytes

      selected =
        Enum.reduce_while(messages, {[], budget}, fn message, {acc, remaining} ->
          parts =
            case message do
              %Request{parts: parts} -> parts
              %Response{parts: parts} -> parts
            end

          case Enum.reduce_while(parts, {[], remaining - 1}, fn part, {acc, remaining} ->
                 value = message_part(part)
                 remaining = content_size(value, remaining - 1, 0)

                 if remaining < 0,
                   do: {:halt, :oversized},
                   else: {:cont, {[value | acc], remaining}}
               end) do
            :oversized -> {:halt, :oversized}
            {parts, remaining} -> {:cont, {[Enum.reverse(parts) | acc], remaining}}
          end
        end)

      case selected do
        :oversized -> diagnostic(:content_dropped, :input)
        {messages, _remaining} -> content(operation, :input, Enum.reverse(messages))
      end
    end)
  end

  defp message_part(%Part.System{content: text}), do: %{role: "system", content: text}
  defp message_part(%Part.User{content: text}), do: %{role: "user", content: text}
  defp message_part(%Part.Text{content: text}), do: %{role: "assistant", content: text}
  defp message_part(%Part.ToolCall{args: args}), do: %{role: "tool_call", content: args}
  defp message_part(%Part.ToolReturn{content: value}), do: %{role: "tool_result", content: value}
  defp message_part(_), do: nil

  defp content_size(_, left, depth) when left < 0 or depth > 16, do: -1
  defp content_size(value, left, _) when is_binary(value), do: left - byte_size(value)
  defp content_size(%_{}, _, _), do: -1

  defp content_size(value, left, depth) when is_map(value) do
    Enum.reduce_while(value, left, fn {key, val}, remaining ->
      remaining = content_size(key, remaining - 1, depth + 1)
      remaining = content_size(val, remaining, depth + 1)
      if remaining < 0, do: {:halt, -1}, else: {:cont, remaining}
    end)
  end

  defp content_size(value, left, depth) when is_list(value) do
    Enum.reduce_while(value, left, fn val, remaining ->
      remaining = content_size(val, remaining - 1, depth + 1)
      if remaining < 0, do: {:halt, -1}, else: {:cont, remaining}
    end)
  end

  defp content_size(value, left, _) when is_atom(value) or is_number(value) do
    # external_size counts without constructing a binary or decimal string.
    # Three bytes per external byte conservatively cover decimal integer digits
    # (log10(256) < 3), sign, float representation and UTF-8 atoms. Unlike a fixed
    # scalar charge, this rejects arbitrarily large integers before redaction.
    left - 3 * :erlang.external_size(value)
  end

  defp content_size(_, _, _), do: -1

  defp outcome({:error, %ExAgent.RunError{reason: reason, partial: %{status: :cancelled}}}),
    do: {"cancelled", reason}

  defp outcome({:error, reason}) when reason in [:cancelled, :aborted, :exagent_stream_cancelled],
    do: {"cancelled", :cancelled}

  defp outcome({:error, reason}), do: {"failed", reason}

  defp outcome({:ok, %Response{finish_reason: reason}, _})
       when reason in [:length, :content_filter],
       do: {"failed", reason}

  defp outcome({:stream_response, %Response{} = response, _, _, _}),
    do: outcome({:ok, response, nil})

  defp outcome({%Part.ToolReturn{status: status}, _, reason}),
    do:
      {Atom.to_string(status),
       reason || if(status in [:failed, :unknown, :denied, :validation_error], do: status)}

  defp outcome(_), do: {"succeeded", nil}

  defp record_error(operation, reason) do
    diagnostic = ExAgent.ErrorProjection.diagnostic(reason)

    attributes(
      operation,
      Map.new(diagnostic, fn {key, value} -> {"error." <> Atom.to_string(key), value} end)
    )

    :otel_span.set_status(operation.span, :error, diagnostic.type)
  end

  defp abandoned(span, kind) do
    safely(:finish, :ok, fn ->
      :otel_span.set_attributes(span, %{
        "exagent.status" => "cancelled",
        "exagent.usage.status" => "partial",
        "error.type" => "owner_down",
        "exagent.operation" => Atom.to_string(kind)
      })

      :otel_span.set_status(span, :error, "owner_down")
      end_native(span)
    end)
  end

  defp end_native(span) do
    # The API returns a span context, not the processor admission outcome.
    # Admission/export counters belong to BoundedProcessor, not this return value.
    :otel_span.end_span(span)
  end

  defp base_attributes(kind) do
    operation =
      case kind do
        :run -> "invoke_agent"
        :model -> "chat"
        :tool -> "execute_tool"
        _ -> nil
      end

    compact(%{
      "exagent.profile" => @profile,
      "exagent.gen_ai.revision" => @gen_ai_revision,
      "exagent.operation" => Atom.to_string(kind),
      "gen_ai.operation.name" => operation
    })
  end

  defp detail(details, keys) when is_map(details) do
    Enum.find_value(keys, fn key ->
      token(Map.get(details, key, Map.get(details, Atom.to_string(key))))
    end)
  end

  defp detail(_, _), do: nil
  defp token(value) when is_integer(value) and value >= 0, do: value
  defp token(_), do: nil
  defp number(value) when is_number(value) and value >= 0, do: value
  defp number(_), do: nil
  defp compact(attrs), do: Map.reject(attrs, fn {_, value} -> is_nil(value) end)

  defp safely(stage, fallback, fun) do
    fun.()
  rescue
    _ ->
      diagnostic(:failure, stage)
      fallback
  catch
    _, _ ->
      diagnostic(:failure, stage)
      fallback
  end

  @doc false
  def diagnostic(event, stage) do
    :telemetry.execute([:exagent, :observability, event], %{count: 1}, %{stage: stage})
  end
end

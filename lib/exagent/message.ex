defmodule ExAgent.Message do
  @moduledoc """
  Message and part types exchanged between the agent and a model.

  It leans into Elixir's native discriminated unions: every part/message is a
  struct, and the `__struct__` field is the discriminator you pattern-match on
  (`case part do %Part.ToolCall{} -> ...`).

  Two top-level messages:

    * `Request`  — sent *to* the model (system/user prompts, tool returns,
      retry prompts).
    * `Response` — returned *by* the model (text, tool calls, thinking).

  All structs `@derive Jason.Encoder` so a whole history can be serialised to
  JSON for persistence or for talking to providers.
  """

  defmodule Usage do
    @moduledoc """
    Qualified metrics for a response or aggregate. `accounting` is a versioned,
    string-keyed JSON map, separate from additive token details. Reported means
    reported to the host by the Model contract, not audited provider presence.
    Cost is always an estimate in cents, never an invoice.

    `payload_omitted` marks bounded postdecode omission of oversized details or
    dimensions. Retained metric availability remains explicit; omitted values
    are not zero. The marker is versioned independently of accounting v1.
    """
    @derive [Jason.Encoder]
    @enforce_keys [:input_tokens, :output_tokens]
    defstruct [:input_tokens, :output_tokens, :accounting, :payload_omitted, details: %{}]

    @type t :: %__MODULE__{
            input_tokens: non_neg_integer() | nil,
            output_tokens: non_neg_integer() | nil,
            accounting: map() | nil,
            details: map()
          }

    @dimensions ~w(input output cache_read cache_write reasoning)
    @availability ~w(available unavailable partial)
    @additive_details [
      {"total_tokens", ["total_tokens"]},
      {"cached_tokens", ["cached_tokens", "cache_read_input_tokens", "cached_input"]},
      {"cache_creation_input_tokens",
       ["cache_creation_input_tokens", "cache_creation_tokens", "cache_creation"]},
      {"reasoning_tokens", ["reasoning_tokens", "reasoning"]}
    ]

    @doc false
    def qualify(nil), do: qualify(%__MODULE__{input_tokens: nil, output_tokens: nil})
    def qualify(%__MODULE__{accounting: accounting} = usage) when is_map(accounting), do: usage

    def qualify(%__MODULE__{} = usage) do
      %{usage | accounting: marker(usage, "model", "reported")}
    end

    defp marker(usage, source, quality) do
      details = additive_details(usage.details)

      %{
        "version" => 1,
        "source" => source,
        "quality" => quality,
        "provider_presence" => "unknown",
        "input_semantics" => "unknown",
        "reasoning_semantics" => "unknown",
        "availability" => %{
          "input" => available(usage.input_tokens),
          "output" => available(usage.output_tokens),
          "cache_read" => available(details["cached_tokens"]),
          "cache_write" => available(details["cache_creation_input_tokens"]),
          "reasoning" => available(details["reasoning_tokens"])
        },
        "cost" => cost_map(nil, "unknown")
      }
    end

    @doc false
    def normalized(public, currency \\ "USD") do
      public = if is_map(public), do: public, else: %{}

      usage = %__MODULE__{
        input_tokens: metric(public, [:input_tokens, :input]),
        output_tokens: metric(public, [:output_tokens, :output]),
        details: %{}
      }

      details =
        for {key, aliases} <- [
              {"cached_tokens", [:cached_tokens, :cached_input]},
              {"cache_creation_input_tokens", [:cache_creation_tokens, :cache_creation]},
              {"reasoning_tokens", [:reasoning_tokens, :reasoning]}
            ],
            value = metric(public, aliases),
            value != nil,
            into: %{},
            do: {key, value}

      usage = %{usage | details: details}
      accounting = marker(usage, "req_llm", "normalized")

      input_semantics =
        case get(public, :input_includes_cached) do
          true -> "inclusive"
          false -> "exclusive_cache"
          _ -> "unknown"
        end

      reasoning_semantics =
        case get(public, :add_reasoning_to_cost) do
          false -> "included_in_output"
          true -> "separate"
          _ -> "unknown"
        end

      total = get(public, :total_cost)
      total = if total == nil, do: get(get(public, :cost), :total), else: total
      cents = if currency == "USD" and is_number(total) and total >= 0, do: total * 100

      %{
        usage
        | accounting: %{
            accounting
            | "input_semantics" => input_semantics,
              "reasoning_semantics" => reasoning_semantics,
              "cost" => cost_map(cents, "req_llm")
          }
      }
    end

    defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
    defp get(_, _), do: nil

    defp metric(map, keys) do
      value =
        Enum.find_value(keys, fn key ->
          case get(map, key) do
            nil -> nil
            value -> {:value, value}
          end
        end)

      case value do
        {:value, n} when is_integer(n) and n >= 0 -> n
        _ -> nil
      end
    end

    @doc false
    def detail(usage, key) do
      detail_value(usage.details, key)
    end

    @doc false
    def canonical_details(usage), do: additive_details(usage.details)

    defp detail_value(details, key),
      do:
        Map.get(
          details,
          key,
          Enum.find_value(details, fn {k, v} ->
            if is_atom(k) and Atom.to_string(k) == key, do: v
          end)
        )

    defp additive_details(details) do
      for {key, aliases} <- @additive_details,
          value =
            Enum.find_value(aliases, fn name ->
              case detail_value(details, name) do
                nil -> nil
                value -> {:present, value}
              end
            end),
          match?({:present, n} when is_integer(n) and n >= 0, value),
          into: %{},
          do: {key, elem(value, 1)}
    end

    defp available(n) when is_integer(n) and n >= 0, do: "available"
    defp available(_), do: "unavailable"

    @doc false
    def with_cost(usage, cents, source, complete? \\ true) do
      usage = qualify(usage)
      cost = cost_map(cents, source)

      cost =
        if is_number(cents) and not complete?,
          do: %{cost | "cents" => nil, "availability" => "partial"},
          else: cost

      %{usage | accounting: Map.put(usage.accounting, "cost", cost)}
    end

    defp cost_map(cents, source) do
      %{
        "cents" => cents,
        "subtotal_cents" => cents,
        "source" => source,
        "quality" => "estimated",
        "availability" => if(is_number(cents), do: "available", else: "unavailable")
      }
    end

    @doc false
    def estimated_cost(usage), do: get_in(qualify(usage).accounting, ["cost", "cents"])

    @doc false
    def complete?(usage) do
      accounting = qualify(usage).accounting
      Enum.all?(~w(input output), &(accounting["availability"][&1] == "available"))
    end

    @doc false
    def partial(usage) do
      usage = qualify(usage)

      availability =
        Map.new(usage.accounting["availability"], fn {k, v} ->
          {k, if(v == "available", do: "partial", else: v)}
        end)

      cost = usage.accounting["cost"]

      cost = %{
        cost
        | "cents" => nil,
          "availability" =>
            if(cost["availability"] == "available", do: "partial", else: cost["availability"])
      }

      %{usage | accounting: %{usage.accounting | "availability" => availability, "cost" => cost}}
    end

    @doc false
    def sum([]),
      do: qualify(%__MODULE__{input_tokens: 0, output_tokens: 0}) |> with_cost(0, "aggregate")

    def sum([usage]), do: qualify(usage)
    def sum([usage | rest]), do: Enum.reduce(rest, qualify(usage), &add(&2, &1))

    @doc false
    def add(left, right) do
      if left == sum([]), do: qualify(right), else: add_qualified(left, right)
    end

    defp add_qualified(left, right) do
      left = qualify(left)
      right = qualify(right)
      a = left.accounting
      b = right.accounting

      availability =
        Map.new(@dimensions, &{&1, coverage(a["availability"][&1], b["availability"][&1])})

      cost_availability = coverage(a["cost"]["availability"], b["cost"]["availability"])
      subtotal = add_number(a["cost"]["subtotal_cents"], b["cost"]["subtotal_cents"])

      cost = %{
        "cents" => if(cost_availability == "available", do: subtotal),
        "subtotal_cents" => subtotal,
        "source" => same(a["cost"]["source"], b["cost"]["source"], "mixed"),
        "quality" => "estimated",
        "availability" => cost_availability
      }

      %__MODULE__{
        input_tokens: add_number(left.input_tokens, right.input_tokens),
        output_tokens: add_number(left.output_tokens, right.output_tokens),
        details: add_details(left.details, right.details),
        payload_omitted: left.payload_omitted || right.payload_omitted,
        accounting: %{
          "version" => 1,
          "source" => "aggregate",
          "quality" => same(a["quality"], b["quality"], "mixed"),
          "provider_presence" => "unknown",
          "availability" => availability,
          "cost" => cost,
          "input_semantics" => same(a["input_semantics"], b["input_semantics"], "unknown"),
          "reasoning_semantics" =>
            same(a["reasoning_semantics"], b["reasoning_semantics"], "unknown")
        }
      }
    end

    defp coverage(a, a), do: a
    defp coverage(_, _), do: "partial"
    defp same(a, a, _), do: a
    defp same(_, _, fallback), do: fallback
    defp add_number(nil, nil), do: nil
    defp add_number(a, b), do: (a || 0) + (b || 0)

    defp add_details(a, b) do
      Map.merge(additive_details(a), additive_details(b), fn _, x, y -> x + y end)
    end

    @doc false
    def validate(usage) do
      if valid?(usage), do: :ok, else: {:error, :invalid_model_usage}
    end

    defp valid?(%__MODULE__{} = usage) do
      Enum.all?([usage.input_tokens, usage.output_tokens], &counter?/1) and
        valid_omission?(usage.payload_omitted) and
        is_map(usage.details) and
        (usage.accounting == nil or
           (accounting_valid?(usage.accounting) and available_values?(usage)))
    end

    defp valid?(_), do: false

    defp valid_omission?(marker) do
      ExAgent.Retention.marker!(marker)
      true
    rescue
      _ -> false
    end

    defp available_values?(usage) do
      details = additive_details(usage.details)

      Enum.all?(
        [
          {"input", usage.input_tokens},
          {"output", usage.output_tokens},
          {"cache_read", details["cached_tokens"]},
          {"cache_write", details["cache_creation_input_tokens"]},
          {"reasoning", details["reasoning_tokens"]}
        ],
        fn {key, value} ->
          usage.accounting["availability"][key] != "available" or
            (is_integer(value) and value >= 0)
        end
      )
    end

    defp counter?(nil), do: true
    defp counter?(n), do: is_integer(n) and n >= 0
    defp number?(nil), do: true
    defp number?(n), do: is_number(n) and n >= 0
    defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

    defp accounting_valid?(a) do
      keys?(
        a,
        ~w(version source quality provider_presence input_semantics reasoning_semantics availability cost)
      ) and
        a["version"] == 1 and a["source"] in ~w(model req_llm aggregate legacy_snapshot) and
        a["quality"] in ~w(reported normalized mixed unknown) and
        a["provider_presence"] == "unknown" and
        a["input_semantics"] in ~w(inclusive exclusive_cache unknown) and
        a["reasoning_semantics"] in ~w(included_in_output separate unknown) and
        keys?(a["availability"], @dimensions) and
        Enum.all?(Map.values(a["availability"]), &(&1 in @availability)) and
        cost_valid?(a["cost"])
    end

    defp cost_valid?(cost) do
      keys?(cost, ~w(cents subtotal_cents source quality availability)) and
        cost["source"] in ~w(req_llm estimator aggregate mixed unknown) and
        cost["quality"] == "estimated" and
        cost["availability"] in @availability and number?(cost["cents"]) and
        number?(cost["subtotal_cents"]) and
        if cost["availability"] == "available",
          do: is_number(cost["cents"]) and cost["cents"] == cost["subtotal_cents"],
          else: cost["cents"] == nil
    end

    @doc false
    def to_map(usage) do
      usage = qualify(usage)
      if validate(usage) != :ok, do: raise(ArgumentError, "invalid usage accounting")

      map = %{
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "details" => usage.details,
        "accounting" => usage.accounting
      }

      if usage.payload_omitted,
        do: Map.put(map, "payload_omitted", usage.payload_omitted),
        else: map
    end

    @doc false
    def from_map!(map) when is_map(map) do
      usage = %__MODULE__{
        input_tokens: map["input_tokens"],
        output_tokens: map["output_tokens"],
        details: Map.get(map, "details", %{}),
        accounting: map["accounting"],
        payload_omitted: ExAgent.Retention.marker!(map["payload_omitted"])
      }

      usage =
        if usage.accounting == nil do
          a = marker(usage, "legacy_snapshot", "unknown")
          a = %{a | "availability" => Map.new(@dimensions, &{&1, "unavailable"})}
          %{usage | accounting: a}
        else
          usage
        end

      if validate(usage) != :ok, do: raise(ArgumentError, "invalid usage accounting")
      usage
    end
  end

  # ---------------------------------------------------------------------------
  # Request parts
  # ---------------------------------------------------------------------------
  defmodule Part do
    @moduledoc "Request & response part structs."

    defmodule System do
      @moduledoc "A system / instruction prompt part."
      @derive [Jason.Encoder]
      @enforce_keys [:content]
      defstruct [:content, :dynamic_ref]

      @type t :: %__MODULE__{
              content: String.t() | [map()],
              dynamic_ref: String.t() | nil
            }
    end

    defmodule User do
      @moduledoc "A user prompt part (text or multimodal content list)."
      @derive [Jason.Encoder]
      @enforce_keys [:content]
      defstruct [:content, :timestamp]

      @type t :: %__MODULE__{
              content: String.t() | [map()],
              timestamp: DateTime.t() | nil
            }
    end

    defmodule ToolReturn do
      @moduledoc """
      The return value of a tool call, fed back to the model.

      `usage` is an optional contributed token usage (e.g. from a delegated
      sub-agent run) that the agent loop merges into the run's accumulated
      usage. It is `nil` for ordinary tools and is not part of the serialized
      message history (usage is accounted for at runtime).

      `payload_omitted` distinguishes an omitted value from a genuine nil result.
      Status describes the effect even when its payload was omitted. Such history
      is diagnostic and cannot be executed as ordinary model context.
      """
      @derive [Jason.Encoder]
      @enforce_keys [:tool_name, :content, :tool_call_id]
      defstruct [
        :tool_name,
        :content,
        :tool_call_id,
        :usage,
        :payload_omitted,
        status: :succeeded
      ]

      @type status ::
              :succeeded | :validation_error | :denied | :failed | :unknown | :not_executed

      @type t :: %__MODULE__{
              tool_name: String.t(),
              content: term(),
              tool_call_id: String.t(),
              usage: Usage.t() | nil,
              status: status()
            }
    end

    defmodule Retry do
      @moduledoc """
      A retry prompt: validation errors (list of maps) or a plain message,
      sent back to the model so it can correct itself.
      """
      @derive [Jason.Encoder]
      @enforce_keys [:content]
      defstruct [:content, :tool_name, :tool_call_id]

      @type t :: %__MODULE__{
              content: [map()] | String.t(),
              tool_name: String.t() | nil,
              tool_call_id: String.t() | nil
            }
    end

    # -------------------------------------------------------------------------
    # Response parts
    # -------------------------------------------------------------------------
    defmodule Text do
      @moduledoc "A plain text chunk returned by the model."
      @derive [Jason.Encoder]
      @enforce_keys [:content]
      defstruct [:content, :id, metadata: %{}]

      @type t :: %__MODULE__{content: String.t(), id: String.t() | nil, metadata: map()}
    end

    defmodule Thinking do
      @moduledoc "A reasoning / chain-of-thought part (provider-dependent)."
      @derive [Jason.Encoder]
      @enforce_keys [:content]
      defstruct [:content, :signature, :id, metadata: %{}]

      @type t :: %__MODULE__{
              content: String.t(),
              signature: String.t() | nil,
              metadata: map(),
              id: String.t() | nil
            }
    end

    defmodule ToolCall do
      @moduledoc """
      The model asking the agent to run a tool.

      `args` may be `nil`, a decoded `map()`, or raw JSON `binary()` (the latter
      when the provider streams partial JSON). Use `args_as_map/1` to normalise.
      """
      @derive [Jason.Encoder]
      @enforce_keys [:tool_name]
      defstruct [:tool_name, :args, :tool_call_id, kind: :function, metadata: %{}]

      @type arg :: nil | map() | binary()
      @type kind :: :function | :output | :external | :unapproved
      @type t :: %__MODULE__{
              tool_name: String.t(),
              args: arg(),
              tool_call_id: String.t() | nil,
              kind: kind(),
              metadata: map()
            }

      @doc """
      Decode `args` to a map. Accepts a map (passthrough), a JSON string, or
      `nil`. On unparseable JSON, returns `:error` (the agent turns that into a
      retry prompt so the model can fix its arguments).
      """
      @spec args_as_map(t()) :: {:ok, map()} | {:error, term()} | :empty
      def args_as_map(%__MODULE__{args: nil}), do: :empty
      def args_as_map(%__MODULE__{args: args}) when is_map(args), do: {:ok, args}

      def args_as_map(%__MODULE__{args: args}) when is_binary(args) do
        case Jason.decode(args) do
          {:ok, map} when is_map(map) -> {:ok, map}
          {:ok, other} -> {:error, {:not_an_object, other}}
          {:error, _} = e -> e
        end
      end

      # A non-conforming args value (e.g. an integer a model/proxy emitted) used
      # to raise FunctionClauseError and crash the tool task. Surface it as a
      # clean error so the run returns {:error, _} and the model can retry.
      def args_as_map(%__MODULE__{args: other}), do: {:error, {:unsupported_args_type, other}}
    end
  end

  # ---------------------------------------------------------------------------
  # Top-level messages
  # ---------------------------------------------------------------------------
  defmodule Request do
    @moduledoc "A message sent *to* the model."
    @derive [Jason.Encoder]
    @enforce_keys [:parts]
    defstruct [:parts, :instructions, :run_id, :conversation_id, :timestamp]

    @type part :: Part.System.t() | Part.User.t() | Part.ToolReturn.t() | Part.Retry.t()
    @type t :: %__MODULE__{
            parts: [part()],
            instructions: String.t() | nil,
            run_id: String.t() | nil,
            conversation_id: String.t() | nil,
            timestamp: DateTime.t() | nil
          }
  end

  defmodule Response do
    @moduledoc "A message returned *by* the model."
    @derive [Jason.Encoder]
    @enforce_keys [:parts]
    defstruct [
      :parts,
      :usage,
      :model_name,
      :finish_reason,
      :timestamp,
      :continuation,
      :payload_omitted
    ]

    @type part :: Part.Text.t() | Part.ToolCall.t() | Part.Thinking.t()
    @type t :: %__MODULE__{
            parts: [part()],
            usage: Usage.t() | nil,
            model_name: String.t() | nil,
            finish_reason: atom() | nil,
            continuation: map() | nil,
            timestamp: DateTime.t() | nil
          }

    @doc "Concatenate all `TextPart` contents of the response."
    @spec text(t()) :: String.t()
    def text(%__MODULE__{parts: parts}) do
      parts
      |> Enum.filter(&match?(%Part.Text{}, &1))
      |> Enum.map_join(& &1.content)
    end

    @doc "All `ToolCall` parts in order."
    @spec tool_calls(t()) :: [Part.ToolCall.t()]
    def tool_calls(%__MODULE__{parts: parts}) do
      Enum.filter(parts, &match?(%Part.ToolCall{}, &1))
    end

    @doc "True if the response contains no tool calls and no text."
    @spec empty?(t()) :: boolean()
    def empty?(%__MODULE__{} = resp) do
      tool_calls(resp) == [] and text(resp) == ""
    end
  end

  @type t :: Request.t() | Response.t()

  @doc "Build a request from a list of parts."
  @spec new_request([Request.part()], keyword()) :: Request.t()
  def new_request(parts, opts \\ []) do
    %Request{
      parts: parts,
      instructions: Keyword.get(opts, :instructions),
      run_id: Keyword.get(opts, :run_id),
      conversation_id: Keyword.get(opts, :conversation_id),
      timestamp: Keyword.get(opts, :timestamp) || DateTime.utc_now()
    }
  end

  @doc "Build a response from a list of parts."
  @spec new_response([Response.part()], keyword()) :: Response.t()
  def new_response(parts, opts \\ []) do
    %Response{
      parts: parts,
      usage:
        case Keyword.get(opts, :usage) do
          nil -> nil
          %Usage{} = usage -> Usage.qualify(usage)
        end,
      model_name: Keyword.get(opts, :model_name),
      finish_reason: Keyword.get(opts, :finish_reason),
      continuation: Keyword.get(opts, :continuation),
      timestamp: Keyword.get(opts, :timestamp) || DateTime.utc_now()
    }
  end

  @doc "Flatten a message history into its constituent parts (mostly for tests)."
  @spec parts([t()]) :: [struct()]
  def parts(messages) do
    Enum.flat_map(messages, fn
      %Request{parts: ps} -> ps
      %Response{parts: ps} -> ps
    end)
  end

  # -------------------------------------------------------------------------
  # Serialization (round-trip for persistence: PG/Redis/ETS/file)
  # -------------------------------------------------------------------------
  # The per-struct `@derive Jason.Encoder` drops `__struct__`, so the plain JSON
  # isn't self-describing. These helpers add a `__type__` discriminator and a
  # DateTime round-trip, so a message history can be stored and reconstructed
  # with best-effort fidelity (maps/strings/numbers survive; opaque terms become
  # their inspected string).

  @doc "Serialize a message history to a JSON binary for persistence."
  @spec to_json([t()]) :: String.t()
  def to_json(messages) when is_list(messages) do
    Jason.encode!(Enum.map(messages, &to_encodable/1))
  end

  @doc "Parse a JSON binary back into a message history."
  @spec from_json(String.t() | binary()) :: {:ok, [t()]} | {:error, term()}
  def from_json(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, list} when is_list(list) -> {:ok, Enum.map(list, &from_encodable/1)}
      {:ok, other} -> {:error, {:not_a_list, other}}
      {:error, _} = e -> e
    end
  rescue
    error -> {:error, {:invalid_message, Exception.message(error)}}
  end

  defp to_encodable(%Request{parts: parts} = r) do
    request = %{
      "__type__" => "request",
      "parts" => Enum.map(parts, &to_encodable/1),
      "instructions" => r.instructions
    }

    request
    |> Map.put("run_id", r.run_id)
    |> Map.put("conversation_id", r.conversation_id)
    |> maybe_put_ts(r.timestamp)
  end

  defp to_encodable(%Response{parts: parts} = r) do
    %{
      "__type__" => if(r.payload_omitted, do: "response_omitted_v1", else: "response"),
      "parts" => Enum.map(parts, &to_encodable/1),
      "usage" => to_encodable(r.usage),
      "model_name" => r.model_name,
      "finish_reason" => Atom.to_string(r.finish_reason)
    }
    |> maybe_put_ts(r.timestamp)
    |> put_continuation(r.continuation)
    |> put_omission(r.payload_omitted)
  end

  defp to_encodable(nil), do: nil

  defp to_encodable(%Usage{} = usage), do: Usage.to_map(usage)

  defp to_encodable(%Part.System{content: c, dynamic_ref: d}),
    do: %{"__type__" => "system", "content" => c, "dynamic_ref" => d}

  defp to_encodable(%Part.User{content: c, timestamp: ts}),
    do: %{"__type__" => "user", "content" => c} |> maybe_put_ts(ts)

  defp to_encodable(
         %Part.ToolReturn{tool_name: n, content: c, tool_call_id: id, status: status} = part
       ) do
    %{
      "__type__" => if(part.payload_omitted, do: "tool_return_omitted_v1", else: "tool_return"),
      "tool_name" => n,
      "content" => if(part.payload_omitted && is_nil(c), do: nil, else: encode_content(c)),
      "tool_call_id" => id,
      "status" => Atom.to_string(status)
    }
    |> put_omission(part.payload_omitted)
  end

  defp to_encodable(%Part.Retry{content: c, tool_name: n, tool_call_id: id}),
    do: %{
      "__type__" => "retry",
      "content" => encode_content(c),
      "tool_name" => n,
      "tool_call_id" => id
    }

  defp to_encodable(%Part.Text{content: c, id: id, metadata: metadata}),
    do: maybe_put_id(%{"__type__" => "text", "content" => c}, id) |> put_metadata(metadata)

  defp to_encodable(%Part.Thinking{content: c, signature: s, id: id, metadata: metadata}),
    do:
      maybe_put_id(%{"__type__" => "thinking", "content" => c, "signature" => s}, id)
      |> put_metadata(metadata)

  defp to_encodable(%Part.ToolCall{
         tool_name: n,
         args: a,
         tool_call_id: id,
         kind: k,
         metadata: metadata
       }),
       do:
         %{
           "__type__" => "tool_call",
           "tool_name" => n,
           "args" => a,
           "tool_call_id" => id,
           "kind" => k
         }
         |> put_metadata(metadata)

  defp from_encodable(%{"__type__" => "request"} = r) do
    %Request{
      parts: Enum.map(r["parts"], &from_encodable/1),
      instructions: r["instructions"],
      run_id: r["run_id"],
      conversation_id: r["conversation_id"],
      timestamp: parse_ts(r["timestamp"])
    }
  end

  defp from_encodable(%{"__type__" => type} = r)
       when type in ["response", "response_omitted_v1"] do
    if type == "response_omitted_v1" and is_nil(r["payload_omitted"]),
      do: raise(ArgumentError, "missing omission marker")

    %Response{
      parts: Enum.map(r["parts"], &from_encodable/1),
      usage: from_encodable(r["usage"]),
      model_name: r["model_name"],
      finish_reason: parse_atom(r["finish_reason"]),
      continuation: ExAgent.Message.Continuation.validate!(r["continuation"]),
      payload_omitted: ExAgent.Retention.marker!(r["payload_omitted"]),
      timestamp: parse_ts(r["timestamp"])
    }
  end

  defp from_encodable(nil), do: nil

  defp from_encodable(%{"input_tokens" => _, "output_tokens" => _} = u),
    do: Usage.from_map!(u)

  defp from_encodable(%{"__type__" => "system"} = p),
    do: %Part.System{content: p["content"], dynamic_ref: p["dynamic_ref"]}

  defp from_encodable(%{"__type__" => "user"} = p),
    do: %Part.User{content: p["content"], timestamp: parse_ts(p["timestamp"])}

  defp from_encodable(%{"__type__" => type} = p)
       when type in ["tool_return", "tool_return_omitted_v1"] do
    if type == "tool_return_omitted_v1" and is_nil(p["payload_omitted"]),
      do: raise(ArgumentError, "missing omission marker")

    %Part.ToolReturn{
      tool_name: p["tool_name"],
      content: p["content"],
      tool_call_id: p["tool_call_id"],
      status: tool_return_status(Map.get(p, "status", "succeeded")),
      payload_omitted: ExAgent.Retention.marker!(p["payload_omitted"])
    }
  end

  defp from_encodable(%{"__type__" => "retry"} = p),
    do: %Part.Retry{
      content: p["content"],
      tool_name: p["tool_name"],
      tool_call_id: p["tool_call_id"]
    }

  defp from_encodable(%{"__type__" => "text"} = p),
    do: %Part.Text{
      content: p["content"],
      id: if(is_binary(p["id"]), do: p["id"]),
      metadata: read_metadata(p)
    }

  defp from_encodable(%{"__type__" => "thinking"} = p),
    do: %Part.Thinking{
      content: p["content"],
      signature: p["signature"],
      metadata: read_metadata(p),
      id: if(is_binary(p["id"]), do: p["id"])
    }

  defp from_encodable(%{"__type__" => "tool_call"} = p),
    do: %Part.ToolCall{
      tool_name: p["tool_name"],
      args: p["args"],
      tool_call_id: p["tool_call_id"],
      kind: parse_atom(p["kind"]),
      metadata: read_metadata(p)
    }

  defp read_metadata(part),
    do: ExAgent.Message.Continuation.metadata!(Map.get(part, "metadata", %{}))

  defp put_metadata(map, metadata) do
    case ExAgent.Message.Continuation.metadata!(metadata) do
      empty when map_size(empty) == 0 -> map
      data -> Map.put(map, "metadata", data)
    end
  end

  defp put_omission(map, nil), do: map

  defp put_omission(map, marker),
    do: Map.put(map, "payload_omitted", ExAgent.Retention.marker!(marker))

  defp put_continuation(map, nil), do: map

  defp put_continuation(map, data),
    do: Map.put(map, "continuation", ExAgent.Message.Continuation.validate!(data))

  defp maybe_put_ts(map, %DateTime{} = ts), do: Map.put(map, "timestamp", DateTime.to_iso8601(ts))
  defp maybe_put_ts(map, _), do: map

  defp maybe_put_id(map, id) when is_binary(id), do: Map.put(map, "id", id)
  defp maybe_put_id(map, _), do: map

  defp parse_ts(nil), do: nil

  defp parse_ts(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp tool_return_status("succeeded"), do: :succeeded
  defp tool_return_status("validation_error"), do: :validation_error
  defp tool_return_status("denied"), do: :denied
  defp tool_return_status("failed"), do: :failed
  defp tool_return_status("unknown"), do: :unknown
  defp tool_return_status("not_executed"), do: :not_executed

  defp tool_return_status(other),
    do: raise(ArgumentError, "invalid tool return status: #{inspect(other)}")

  defp parse_atom(nil), do: nil

  defp parse_atom(str) when is_binary(str) do
    # finish_reason / kind come from a known set; avoid atom-table growth on
    # untrusted input by preferring existing atoms, falling back to nil.
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp encode_content(content)
       when is_binary(content) or is_number(content) or is_boolean(content),
       do: content

  defp encode_content(content) when is_map(content) or is_list(content), do: content

  defp encode_content(content), do: inspect(content)
end

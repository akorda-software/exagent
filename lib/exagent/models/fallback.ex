defmodule ExAgent.Models.Fallback do
  @moduledoc """
  Retries transient provider failures and falls back to other models.

      primary = ExAgent.Models.ReqLLM.new(model: ..., foreign_history: :portable)
      backup = ExAgent.Models.ReqLLM.new(model: ..., foreign_history: :portable)

      model = ExAgent.Models.Fallback.new(models: [primary, backup])
      ExAgent.new(model: model, tools: tools)

  Each model request tries `models` in order. A model is retried up to
  `:max_retries` times with exponential backoff (`:backoff_ms` doubling up to
  `:max_backoff_ms`, with jitter) and then the next model is tried at once. Only
  failures that returned no output are retried or fall back:

    * `ExAgent.RequestError` with an HTTP status in `:retry_statuses` (default
      408, 429, 500, 502, 503, 504 and 529) and no partial response;
    * with `retry_transport: true`, also connection failures
      (`RequestError.transport` set) and total timeouts. The provider may already
      have processed (and billed) such a request, so this is opt-in.

  A gateway may still bill an upstream attempt behind a 502 or 504. Other
  errors, including configuration errors detected before IO, return
  immediately. A streaming request is retried only when its first event is a
  retryable error; once output has been emitted the stream is committed.

  The loop counts one admitted model request however many attempts it makes.
  Each attempt keeps `settings.timeout` as its receive timeout; the run
  deadline (`ModelRequestParameters.deadline`) bounds all attempts together, so
  retries never outlive it. Every retry emits `[:exagent, :model, :retry]`
  telemetry.

  Different models only accept each other's responses in the history when
  configured for it, e.g. `ExAgent.Models.ReqLLM` with `foreign_history:
  :portable`; otherwise switching models mid-conversation fails like any other
  mismatched history. A persisted history resumes when any of the models
  accepts it. The profile is the intersection of the models' profiles.
  `model_name/1` and `system/1` report the first model; each response keeps
  the name of the model that produced it. An explicit `estimate_cost`
  callback receives this fallback model, not the model that served the
  request, so price per response (`model_name`) or rely on usage reported by
  the models.

  `models` must be model structs (resolve spec strings with
  `ExAgent.Model.resolve/2` first); build the struct with `new/1`.
  """
  @behaviour ExAgent.Model

  alias ExAgent.{Model, ModelProfile, ModelSettings, RequestError}

  @retry_statuses [408, 429, 500, 502, 503, 504, 529]

  defstruct models: [],
            max_retries: 2,
            backoff_ms: 500,
            max_backoff_ms: 8_000,
            retry_statuses: @retry_statuses,
            retry_transport: false

  @type t :: %__MODULE__{
          models: [Model.model()],
          max_retries: non_neg_integer(),
          backoff_ms: non_neg_integer(),
          max_backoff_ms: non_neg_integer(),
          retry_statuses: [pos_integer()],
          retry_transport: boolean()
        }

  @doc "Builds a fallback model, raising `ArgumentError` on invalid options."
  @spec new(keyword()) :: t()
  def new(opts) do
    model = struct!(__MODULE__, opts)

    case validate(model) do
      :ok -> model
      {:error, reason} -> raise ArgumentError, "invalid fallback model: #{inspect(reason)}"
    end
  end

  @impl true
  def request(model, messages, settings, params) do
    with :ok <- validate(model) do
      attempt(model, settings, params, fn child, settings ->
        case Model.request(child, messages, settings, params) do
          {:ok, response, child} -> {:ok, child, response}
          {:error, reason} -> {:error, reason}
          other -> {:error, {:invalid_model_result, other}}
        end
      end)
      |> case do
        {:ok, index, child, response} -> {:ok, response, put_model(model, index, child)}
        {:error, _} = error -> error
      end
    end
  end

  @impl true
  def request_stream(model, messages, settings, params) do
    with :ok <- validate(model) do
      Stream.resource(
        fn -> open_stream(model, messages, settings, params) end,
        &next_stream(&1, model),
        &close_stream/1
      )
    end
  end

  @impl true
  def model_name(%{models: [first | _]}), do: Model.model_name(first)

  @impl true
  def system(%{models: [first | _]}), do: Model.system(first)

  @impl true
  def profile(%{models: models}) do
    profiles = Enum.map(models, &Model.profile/1)
    all? = fn key -> Enum.all?(profiles, &(Map.fetch!(&1, key) == true)) end
    qualities = Enum.map(profiles, & &1.accounting_quality)

    %ModelProfile{
      supports_tools: all?.(:supports_tools),
      supports_json_schema_output: all?.(:supports_json_schema_output),
      supports_json_object_output: all?.(:supports_json_object_output),
      supports_thinking: all?.(:supports_thinking),
      default_output_mode: hd(profiles).default_output_mode,
      accounting_quality: accounting_quality(qualities)
    }
  end

  # Resumable when any model accepts the history; otherwise the first error.
  @impl true
  def validate_resume(%{models: models}, messages, settings, params) do
    results = Enum.map(models, &Model.validate_resume(&1, messages, settings, params))
    if :ok in results, do: :ok, else: hd(results)
  end

  @impl true
  def continuation_binding(%{models: models}) do
    Enum.reduce_while(models, {:ok, []}, fn child, {:ok, acc} ->
      case Model.continuation_binding(child) do
        {:ok, binding} -> {:cont, {:ok, [binding | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, bindings} ->
        {:ok,
         %{"adapter" => "exagent.fallback", "version" => 1, "models" => Enum.reverse(bindings)}}

      error ->
        error
    end
  end

  # --- attempts --------------------------------------------------------------

  defp attempt(model, settings, params, fun) do
    deadline = params.deadline

    plan =
      for {_, index} <- Enum.with_index(model.models),
          retry <- 0..model.max_retries,
          do: {index, retry}

    attempt(plan, model, settings, deadline, fun)
  end

  defp attempt([{index, retry} | rest], model, settings, deadline, fun) do
    child = Enum.at(model.models, index)

    case fun.(child, bounded(settings, deadline)) do
      {:ok, child, result} ->
        {:ok, index, child, result}

      {:error, reason} = error ->
        with [{next, _} | _] <- rest,
             true <- retryable?(reason, model),
             delay = if(next == index, do: backoff(model, retry), else: 0),
             true <- is_nil(deadline) or now() + delay < deadline do
          ExAgent.Telemetry.execute(
            [:model, :retry],
            %{attempt: retry + 1, delay: delay},
            %{model: Model.model_name(child), status: reason.status, fallback: next != index}
          )

          if delay > 0, do: Process.sleep(delay)
          attempt(rest, model, settings, deadline, fun)
        else
          _ -> error
        end
    end
  end

  defp retryable?(%RequestError{partial_response: nil, status: status}, model)
       when is_integer(status),
       do: status in model.retry_statuses

  defp retryable?(%RequestError{partial_response: nil, status: nil} = error, model),
    do: model.retry_transport and (error.transport != nil or error.reason == {:timeout, :total})

  defp retryable?(_, _), do: false

  defp backoff(model, retry) do
    delay = min(model.backoff_ms * Integer.pow(2, retry), model.max_backoff_ms)
    if delay > 0, do: div(delay, 2) + :rand.uniform(div(delay, 2) + 1) - 1, else: 0
  end

  # Each attempt keeps its receive timeout, narrowed to the run deadline.
  defp bounded(settings, nil), do: settings

  defp bounded(settings, deadline) do
    settings = settings || %ModelSettings{}
    remaining = max(deadline - now(), 0)
    %{settings | timeout: min(settings.timeout || remaining, remaining)}
  end

  defp put_model(model, index, child),
    do: %{model | models: List.replace_at(model.models, index, child)}

  # Strict accounting rejects :normalized, so any normalized model taints the chain.
  defp accounting_quality(qualities) do
    cond do
      :normalized in qualities -> :normalized
      Enum.all?(qualities, &(&1 == :reported)) -> :reported
      true -> :unknown
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  # --- streaming -------------------------------------------------------------

  defp open_stream(model, messages, settings, params) do
    attempt(model, settings, params, fn child, settings ->
      stream = Model.request_stream(child, messages, settings, params)

      case Enumerable.reduce(stream, {:cont, nil}, fn event, _ -> {:suspend, event} end) do
        {:suspended, {:error, reason}, continuation} ->
          halt(continuation)
          {:error, reason}

        {:suspended, event, continuation} ->
          {:ok, child, {event, continuation}}

        _ ->
          {:error, :incomplete_stream}
      end
    end)
    |> case do
      {:ok, index, _child, {event, continuation}} -> {:first, index, event, continuation}
      {:error, reason} -> {:failed, reason}
    end
  end

  defp next_stream({:first, index, event, continuation}, model),
    do: {[wrap(event, model, index)], {:open, index, continuation}}

  defp next_stream({:open, index, continuation}, model) do
    case continuation.({:cont, nil}) do
      {:suspended, event, continuation} ->
        {[wrap(event, model, index)], {:open, index, continuation}}

      _ ->
        {:halt, :done}
    end
  end

  defp next_stream({:failed, reason}, _model), do: {[{:error, reason}], :done}
  defp next_stream(:done, _model), do: {:halt, :done}

  defp wrap({:response, response, child}, model, index),
    do: {:response, response, put_model(model, index, child)}

  defp wrap(event, _model, _index), do: event

  defp close_stream({:first, _, _, continuation}), do: halt(continuation)
  defp close_stream({:open, _, continuation}), do: halt(continuation)
  defp close_stream(_), do: :ok

  defp halt(continuation) do
    continuation.({:halt, nil})
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  # --- validation ------------------------------------------------------------

  defp validate(%__MODULE__{} = model) do
    cond do
      not (is_list(model.models) and model.models != [] and Enum.all?(model.models, &is_struct/1)) ->
        {:error, {:invalid_option, :models}}

      not (is_integer(model.max_retries) and model.max_retries in 0..10) ->
        {:error, {:invalid_option, :max_retries}}

      not (is_integer(model.backoff_ms) and model.backoff_ms >= 0 and
             is_integer(model.max_backoff_ms) and model.max_backoff_ms >= 0) ->
        {:error, {:invalid_option, :backoff_ms}}

      not (is_list(model.retry_statuses) and Enum.all?(model.retry_statuses, &(&1 in 100..599))) ->
        {:error, {:invalid_option, :retry_statuses}}

      not is_boolean(model.retry_transport) ->
        {:error, {:invalid_option, :retry_transport}}

      true ->
        :ok
    end
  end
end

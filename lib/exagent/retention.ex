defmodule ExAgent.Retention do
  @moduledoc false
  alias ExAgent.Message.{Part, Request, Response, Usage}

  @usage_bytes 4096
  @control_bytes 65_536
  @boundaries ~w(response tool_return usage history input projection hook output error stream checkpoint)

  def usage_bytes, do: @usage_bytes
  def control_bytes, do: @control_bytes
  def bytes(term), do: :erlang.external_size(term)

  def limit?(n), do: is_integer(n) and n > 0 and n <= 67_108_864

  def check(value, limit, boundary) do
    size = bytes(value)
    if size <= limit, do: :ok, else: {:error, error(boundary, size, limit)}
  end

  def error(boundary, size, limit),
    do: {:retention_limit_exceeded, %{boundary: boundary, bytes: size, limit: limit}}

  def marker(boundary, size, limit),
    do: %{"version" => 1, "boundary" => to_string(boundary), "bytes" => size, "limit" => limit}

  def marker!(nil), do: nil

  def marker!(%{"version" => 1, "boundary" => b, "bytes" => n, "limit" => l} = m)
      when map_size(m) == 4 and b in @boundaries and is_integer(n) and n >= 0 and
             is_integer(l) and l >= 0,
      do: m

  def marker!(_), do: raise(ArgumentError, "invalid payload omission marker")

  def executable?(messages) do
    Enum.all?(messages, fn message ->
      is_nil(Map.get(message, :payload_omitted)) and
        not omitted_usage?(Map.get(message, :usage)) and
        Enum.all?(
          message.parts,
          &(is_nil(Map.get(&1, :payload_omitted)) and not omitted_usage?(Map.get(&1, :usage)))
        )
    end)
  end

  defp omitted_usage?(%Usage{payload_omitted: marker}), do: not is_nil(marker)
  defp omitted_usage?(_), do: false

  # A rejected response has no executable calls/continuation. Its usage is
  # accounted independently; never preserve the oversized original in an error.
  def omit_response(response, limit, boundary \\ :response) do
    %Response{
      parts: [],
      finish_reason: if(is_atom(response.finish_reason), do: response.finish_reason),
      usage: elem(usage(response.usage), 0),
      payload_omitted: marker(boundary, bytes(response), limit)
    }
  end

  def tool_outcome({part, retry?, reason}, limit) do
    {usage, usage_error} = usage(part.usage)
    original_bytes = bytes(part)
    part = %{part | usage: usage}

    cond do
      bytes(part) > limit ->
        {%{part | content: nil, payload_omitted: marker(:tool_return, original_bytes, limit)},
         false, error(:tool_return, original_bytes, limit)}

      usage_error ->
        {%{part | payload_omitted: usage && usage.payload_omitted}, false, usage_error}

      true ->
        {part, retry?, reason(reason)}
    end
  end

  def durable_tool_outcome(outcome, limit) do
    {part, retry, reason} = tool_outcome(outcome, limit)
    bytes = byte_size(ExAgent.Continuation.Outcome.encode(%{part | usage: nil}))

    if bytes <= limit do
      {part, retry, reason}
    else
      {%{part | content: nil, payload_omitted: marker(:tool_return, bytes, limit)}, false,
       error(:tool_return, bytes, limit)}
    end
  end

  def reason(nil), do: nil

  # Incomplete Model output already has its own bounded pending_response in
  # RunError.partial. Do not lose the operational cause merely because that
  # response is duplicated in the 4KiB error-control copy. Omit only the copy;
  # arbitrary remaining control still has to fit the original error ceiling.
  def reason(
        {:model_request_failed, %ExAgent.RequestError{partial_response: %Response{} = r} = e} =
          reason
      ) do
    if bytes(reason) > @usage_bytes do
      omitted = %{omit_response(r, @usage_bytes, :error) | usage: nil}
      projected = {:model_request_failed, %{e | partial_response: omitted}}

      if bytes(projected) <= @usage_bytes,
        do: projected,
        else: bounded_reason(reason)
    else
      reason
    end
  end

  def reason(reason) do
    bounded_reason(reason)
  end

  defp bounded_reason(reason) do
    case check(reason, @usage_bytes, :error) do
      :ok -> reason
      {:error, bounded} -> bounded
    end
  end

  def usage(nil), do: {nil, nil}

  def usage(%Usage{} = usage) do
    if Usage.validate(usage) == :ok do
      bounded_usage(usage)
    else
      {Usage.qualify(nil), :invalid_model_usage}
    end
  end

  def usage(_), do: {Usage.qualify(nil), :invalid_model_usage}

  defp bounded_usage(usage) do
    size = bytes(usage)

    if size <= @usage_bytes do
      {usage, nil}
    else
      # Valid accounting has a closed schema. Preserve that schema and its
      # provenance; remove only oversized dimensions and arbitrary details.
      qualified = Usage.qualify(usage)

      details = Usage.canonical_details(qualified)
      cost = qualified.accounting["cost"]

      empty_cost = %{
        cost
        | "cents" => nil,
          "subtotal_cents" => nil,
          "availability" => "unavailable"
      }

      accounting = %{
        qualified.accounting
        | "availability" =>
            Map.new(qualified.accounting["availability"], fn {key, _} -> {key, "unavailable"} end),
          "cost" => empty_cost
      }

      bounded = %{
        qualified
        | input_tokens: nil,
          output_tokens: nil,
          details: %{},
          accounting: accounting,
          payload_omitted: marker(:usage, size, @usage_bytes)
      }

      bounded =
        Enum.reduce(
          [
            {"input", :input_tokens, qualified.input_tokens},
            {"output", :output_tokens, qualified.output_tokens},
            {"cache_read", "cached_tokens", details["cached_tokens"]},
            {"cache_write", "cache_creation_input_tokens",
             details["cache_creation_input_tokens"]},
            {"reasoning", "reasoning_tokens", details["reasoning_tokens"]}
          ],
          bounded,
          fn {dimension, field, value}, acc ->
            candidate =
              if is_atom(field),
                do: Map.put(acc, field, value),
                else: %{
                  acc
                  | details:
                      if(is_nil(value), do: acc.details, else: Map.put(acc.details, field, value))
                }

            candidate =
              put_in(
                candidate.accounting["availability"][dimension],
                qualified.accounting["availability"][dimension]
              )

            retain_if_fits(acc, candidate)
          end
        )

      bounded =
        if details["total_tokens"],
          do:
            retain_if_fits(bounded, %{
              bounded
              | details: Map.put(bounded.details, "total_tokens", details["total_tokens"])
            }),
          else: bounded

      bounded = retain_if_fits(bounded, put_in(bounded.accounting["cost"], cost))
      {bounded, error(:usage, size, @usage_bytes)}
    end
  end

  defp retain_if_fits(previous, candidate),
    do: if(bytes(candidate) <= @usage_bytes, do: candidate, else: previous)

  def usage_error(%Usage{
        payload_omitted: %{"boundary" => boundary, "bytes" => bytes, "limit" => limit}
      }),
      do: {:error, error(if(boundary == "usage", do: :usage, else: :error), bytes, limit)}

  def usage_error(_), do: :ok

  # Frame10 retains four independently escaped JSON result projections. A 1 MiB
  # ordinary slot would reserve 24 MiB before even one effect, beyond Record's
  # 8 MiB bound. Keep a stable 64 KiB durable ceiling; actual batch/tree capacity
  # is still checked before dispatch, independently of this retention ceiling.
  def durable_slots(messages, response, run_id, history_limit, payload_limit),
    do: slots(messages, response, run_id, history_limit, min(payload_limit, 65_536))

  # Each call owns a deterministic serialized slot, independent of completion
  # order. The outer Request/list overhead is charged before admitting effects.
  def slots(messages, response, run_id, history_limit, payload_limit) do
    calls = Response.tool_calls(response)
    base = messages ++ [response]
    request = %Request{parts: [], run_id: run_id, timestamp: DateTime.utc_now()}

    if calls == [] do
      with :ok <- check(base, history_limit, :history), do: {:ok, payload_limit}
    else
      available = history_limit - bytes(base ++ [request])
      slot = min(payload_limit, div(available, length(calls)))

      needed =
        Enum.map(calls, fn call ->
          bytes(%Part.ToolReturn{
            tool_name: call.tool_name,
            tool_call_id: call.tool_call_id,
            content: nil,
            status: :unknown,
            payload_omitted: marker(:tool_return, 0, 0)
          }) +
            @usage_bytes + 128
        end)
        |> Enum.max()

      if slot >= needed,
        do: {:ok, slot},
        else:
          {:error,
           error(:history, bytes(base ++ [request]) + needed * length(calls), history_limit)}
    end
  end
end

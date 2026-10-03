defmodule ExAgent.Continuation.Budget do
  @moduledoc false
  alias ExAgent.Continuation.Record

  def new(limit),
    do: %{"limit_ms" => limit, "remaining_ms" => limit, "reserved_ms" => nil, "refund_at" => nil}

  def valid?(nil), do: true

  def valid?(b) do
    Record.exact?(b, ~w(limit_ms remaining_ms reserved_ms refund_at)) and
      Record.nullable_timestamp?(b["refund_at"]) and
      ((is_nil(b["limit_ms"]) and is_nil(b["remaining_ms"]) and is_nil(b["reserved_ms"])) or
         (Record.positive?(b["limit_ms"]) and Record.counter?(b["remaining_ms"]) and
            b["remaining_ms"] <= b["limit_ms"] and
            (is_nil(b["reserved_ms"]) or
               (Record.counter?(b["reserved_ms"]) and
                  b["reserved_ms"] + b["remaining_ms"] <= b["limit_ms"]))))
  end

  def claim(progress) do
    case progress["active_budget"] do
      %{"remaining_ms" => 0, "limit_ms" => limit} when is_integer(limit) ->
        {:error, :active_budget_exhausted}

      %{"remaining_ms" => remaining, "limit_ms" => limit} = b when is_integer(limit) ->
        {:ok,
         Map.put(progress, "active_budget", %{b | "remaining_ms" => 0, "reserved_ms" => remaining})}

      _ ->
        {:ok, progress}
    end
  end

  def tighten(progress, nil), do: progress

  def tighten(progress, limit) do
    case progress["active_budget"] do
      %{"limit_ms" => old, "remaining_ms" => remaining} = b when is_integer(old) ->
        limit = min(old, limit)
        spent = old - remaining

        Map.put(progress, "active_budget", %{
          b
          | "limit_ms" => limit,
            "remaining_ms" => max(limit - spent, 0)
        })

      %{} ->
        Map.put(progress, "active_budget", new(limit))

      nil ->
        progress
    end
  end

  def refund(progress, elapsed) do
    case progress["active_budget"] do
      %{"reserved_ms" => reserved} = b when is_integer(reserved) ->
        Map.put(progress, "active_budget", %{
          b
          | "remaining_ms" => max(reserved - elapsed, 0),
            "reserved_ms" => nil,
            "refund_at" => System.system_time(:millisecond)
        })

      _ ->
        progress
    end
  end

  def confirm_refund(progress, now) do
    case progress["active_budget"] do
      %{"refund_at" => at, "remaining_ms" => remaining} = b
      when is_integer(at) and is_integer(remaining) ->
        Map.put(progress, "active_budget", %{
          b
          | "remaining_ms" => max(remaining - max(now - at, 0), 0),
            "refund_at" => nil
        })

      _ ->
        progress
    end
  end

  def abandon(progress) do
    case progress["active_budget"] do
      %{} = b -> Map.put(progress, "active_budget", %{b | "reserved_ms" => nil})
      _ -> progress
    end
  end

  def transition?(old, new, operation) do
    a = old["active_budget"]
    b = new["active_budget"]

    cond do
      operation == "start" ->
        valid?(b)

      operation == "claim" ->
        valid?(b) and claim(tighten(old, b && b["limit_ms"])) == {:ok, new}

      operation in ~w(recover cancel) ->
        b == abandon(old)["active_budget"]

      operation in ~w(pause finish) and is_map(a) and is_integer(a["reserved_ms"]) ->
        valid?(b) and b["limit_ms"] == a["limit_ms"] and is_nil(b["reserved_ms"]) and
          b["remaining_ms"] <= a["reserved_ms"]

      true ->
        a == b
    end
  end
end

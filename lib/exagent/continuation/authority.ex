defmodule ExAgent.Continuation.Authority do
  @moduledoc false
  alias ExAgent.{Permissions, UsageLimits}
  alias ExAgent.Continuation.Record

  def capture(node) do
    %{
      "usage" => usage(node.limits),
      "policies" =>
        Enum.map([node.permissions, node.permission_floor] ++ node.permission_floors, &policy/1),
      "max_concurrent_requests" => node.max_concurrent,
      "deadline_at" => node.logical_deadline_at
    }
  end

  def usage(limits),
    do:
      Map.new(Map.from_struct(limits), fn {k, v} ->
        {Atom.to_string(k), if(k == :accounting, do: Atom.to_string(v), else: v)}
      end)

  def policy(nil), do: %{"default" => "allow", "rules" => []}

  def policy(%Permissions{} = p),
    do: %{
      "default" => Atom.to_string(p.default),
      "rules" =>
        Enum.map(p.rules, fn {r, a} -> [Regex.source(r), Regex.opts(r), Atom.to_string(a)] end)
    }

  def policy_load(p) do
    true = Record.exact?(p, ~w(default rules)) and p["default"] in ~w(allow ask deny)
    true = is_list(p["rules"])

    rules =
      Enum.map(p["rules"], fn [pattern, opts, action] ->
        true = action in ~w(allow ask deny)
        {Regex.compile!(pattern, opts), action(action)}
      end)

    %Permissions{default: action(p["default"]), rules: rules}
  end

  defp action("allow"), do: :allow
  defp action("ask"), do: :ask
  defp action("deny"), do: :deny

  def limits_load(data) do
    keys = Map.keys(Map.from_struct(%UsageLimits{}))
    true = Record.exact?(data, Enum.map(keys, &Atom.to_string/1))
    true = data["accounting"] in ~w(strict estimated)

    limits =
      struct!(
        UsageLimits,
        Map.new(keys, fn k ->
          value = data[Atom.to_string(k)]

          {k,
           if(k == :accounting,
             do: if(value == "strict", do: :strict, else: :estimated),
             else: value
           )}
        end)
      )

    :ok = UsageLimits.validate(limits)
    limits
  end

  def valid?(frame) do
    root = frame["run_id"]
    nodes = frame["authority"]

    true =
      is_map(nodes) and
        Enum.sort(Map.keys(nodes)) == Enum.sort([root | Map.keys(frame["children"])])

    Enum.all?(nodes, fn {id, data} ->
      root? = id == root

      true =
        Record.exact?(
          data,
          ~w(policies max_concurrent_requests deadline_at) ++
            if(root?, do: ~w(usage checkpoint_limit), else: [])
        )

      _ =
        limits_load(
          if(root?, do: data["usage"], else: frame["children"][id]["frame"]["limits"]["usage"])
        )

      true = is_list(data["policies"]) and data["policies"] != []
      Enum.each(data["policies"], &policy_load/1)
      true = Record.nullable_timestamp?(data["deadline_at"])

      true =
        is_nil(data["max_concurrent_requests"]) or
          (is_integer(data["max_concurrent_requests"]) and data["max_concurrent_requests"] > 0)

      not root? or
        (is_integer(data["checkpoint_limit"]) and
           data["checkpoint_limit"] in 1..Record.max_bytes())
    end)
  rescue
    _ -> false
  end

  def intersect(data, original_usage, opts) do
    old = limits_load(original_usage)
    current = Keyword.get(opts, :usage_limits) || %UsageLimits{}
    :ok = UsageLimits.validate(current)

    limits =
      struct!(
        UsageLimits,
        Map.new(Map.from_struct(current), fn {k, v} ->
          original = Map.fetch!(old, k)

          {k,
           if(k == :accounting,
             do: if(:strict in [v, original], do: :strict, else: :estimated),
             else: minimum(v, original)
           )}
        end)
      )

    deadline =
      if data["deadline_at"],
        do:
          System.monotonic_time(:millisecond) + data["deadline_at"] -
            System.system_time(:millisecond)

    opts
    |> Keyword.put(:usage_limits, limits)
    |> Keyword.put(
      :permission_floors,
      Keyword.get(opts, :permission_floors, []) ++ Enum.map(data["policies"], &policy_load/1)
    )
    |> Keyword.put(
      :max_concurrent_requests,
      minimum(opts[:max_concurrent_requests], data["max_concurrent_requests"])
    )
    |> Keyword.put(:deadline, minimum(opts[:deadline], deadline))
  end

  def minimum(nil, b), do: b
  def minimum(a, nil), do: a
  def minimum(a, b), do: min(a, b)
end

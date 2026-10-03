defmodule ExAgent.Frame10ExhaustionCapacityTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Store}
  alias ExAgent.Continuation.{Frame, Record}
  alias ExAgent.Frame10FatalCapacityFixture, as: F
  alias ExAgent.Frame10ExhaustionCapacityFixture, as: X
  @moduletag timeout: 600_000

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "exhaustion-matrix-00")}
  end

  @variants [
    [descriptor: :small, siblings: 0, diagnostic: :small],
    [descriptor: :max, siblings: 3],
    [descriptor: :small, siblings: 1, nodes: 2, retries: 1, diagnostic: :unicode],
    [descriptor: :max, siblings: 6, nodes: 2, completed: :plain, settled: true],
    [
      descriptor: :max,
      siblings: 3,
      nodes: 2,
      completed: :typed,
      large_ids: true,
      output_siblings: 2
    ],
    [
      descriptor: :small,
      siblings: 3,
      nodes: 2,
      retries: 3,
      completed: :typed,
      diagnostic: :unicode
    ],
    [descriptor: :max, siblings: 0, nodes: 3, tool_limit: 256],
    [descriptor: :small, siblings: 1, nodes: 2, tool_limit: 65_536, diagnostic: :unicode]
  ]

  for {opts, index} <- Enum.with_index(@variants) do
    test "compositional source boundary and per-phase conservation variant #{index}", %{store: s} do
      opts = unquote(Macro.escape(opts))
      {:ok, descriptor} = Frame.output_descriptor(X.params(opts[:descriptor]))
      size = byte_size(Jason.encode!(descriptor))
      assert if(opts[:descriptor] == :max, do: size == 65_536, else: size < 1024)
      r = X.source(s, Record.max_bytes(), opts)

      if opts[:retries] || opts[:completed] == :typed do
        assert Enum.any?(F.root(r)["output_resolutions"], fn {_, entry} ->
                 entry["descriptor"] == descriptor
               end)
      else
        assert F.root(r)["output_resolutions"] == %{}
      end

      {cmd, _, bound} = Enum.max_by(Process.get(:rows), &elem(&1, 2))
      before = r
      final = X.close(s, r, opts)
      assert F.root(final)["scope"] == F.root(before)["scope"]
      assert is_nil(F.root(before)["frontier"]["fatal"])
      assert Enum.max(Enum.map(Process.get(:rows), &elem(&1, 2))) == bound
      # Normalize decimal width using another REAL pre-fatal prefix, never its sink.
      s = %{s | namespace: "exhaustion-matrix-01"}
      _ = X.source(s, bound, opts)
      {_, _, bound} = Enum.max_by(Process.get(:rows), &elem(&1, 2))
      IO.puts("exhaustion matrix #{unquote(index)} source=#{bound} op=#{cmd["operation"]}")

      for {delta, suffix} <- [{-1, "02"}, {0, "03"}, {1, "04"}] do
        s = %{s | namespace: "exhaustion-matrix-#{suffix}"}

        if delta == -1 do
          assert {:rejected, rejected, {:error, :record_limit}, previous} =
                   catch_throw(X.source(s, bound + delta, opts))

          assert rejected["operation"] == cmd["operation"]
          assert is_nil(F.root(previous)["frontier"]["fatal"])
          assert {:ok, ^previous} = Store.load_record(s, :agent, "conversation")
        else
          r = X.source(s, bound + delta, opts)
          r = X.close(s, r, opts, Enum.reverse(X.runs(opts)))

          for run <- X.runs(opts) do
            n = F.root(r)["children"][run]
            assert n["status"] == "failed"
            assert n["frame"]["output_retries_used"] == Keyword.get(opts, :retries, 0)
            {:ok, history} = Message.from_json(n["snapshot"]["message_history"])

            retries =
              for %Message.Request{parts: parts} <- history,
                  %Message.Part.Retry{} = retry <- parts,
                  do: retry

            assert length(retries) == Keyword.get(opts, :retries, 0) + 1
          end
        end
      end
    end
  end

  test "historical descriptor/source/counter corruption never purchases reserve credits", %{
    store: s
  } do
    opts = [descriptor: :max, nodes: 2, retries: 1, siblings: 3]
    r = X.source(s, Record.max_bytes(), opts)
    r = X.resolve(s, r, "D1", opts)
    entry = F.root(r)["output_resolutions"]["1-terminal"]

    for bad <- [
          put_in(r, ~w(execution progress runtime children D1 frame output_retries_used), 0),
          put_in(
            r,
            ~w(execution progress runtime output_resolutions 1-terminal descriptor allow_text),
            true
          ),
          put_in(
            r,
            ~w(execution progress runtime output_resolutions 1-retry-1 request_id),
            "2-retry-1"
          ),
          put_in(r, ~w(execution progress runtime output_resolutions orphan), %{
            entry
            | "request_id" => "orphan"
          }),
          put_in(
            r,
            ~w(execution progress runtime children D2 frame model_request_id),
            "1-terminal"
          )
        ] do
      assert {:error, _} =
               Record.decode(Jason.encode!(bad), {s.namespace, :agent, "conversation"})
    end

    assert {:ok, ^r} = Store.load_record(s, :agent, "conversation")
    final = X.close(s, r, opts, ["D2"])
    assert F.root(final)["children"]["D1"] == F.root(r)["children"]["D1"]
  end

  test "canonical delegated raw larger than its tool bound still rejects despite checkpoint room",
       %{store: s} do
    opts = [descriptor: :max, nodes: 3, tool_limit: 1]
    r = X.source(s, Record.max_bytes(), opts)

    assert {:rejected, cmd, {:error, :invalid_record}, ^r} =
             catch_throw(X.resolve(s, r, "D1", opts))

    assert cmd["operation"] == "output_resolution"
    assert {:ok, ^r} = Store.load_record(s, :agent, "conversation")
    assert is_nil(F.root(r)["frontier"]["fatal"])
  end
end

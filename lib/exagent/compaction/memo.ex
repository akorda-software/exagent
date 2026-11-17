defmodule ExAgent.Compaction.Memo do
  @moduledoc """
  A bounded, host-supervised store that lets `ExAgent.Compaction.Summary` reuse
  its last summary instead of summarizing on every request.

      children = [{ExAgent.Compaction.Memo, name: MyApp.CompactionMemo, max_entries: 2_000}]

      %ExAgent.Compaction.Capability{
        compactor: ExAgent.Compaction.Summary,
        opts: [summarize: &my_summarize/1, memo: MyApp.CompactionMemo]
      }

  Each entry holds one summary text and a SHA-256 digest of the messages it
  replaced, keyed by a digest of the conversation's first message. The digest
  check makes reuse safe across forks and unrelated conversations; conversations
  that start with the same message share one entry, which costs extra summaries,
  never a wrong one. When
  `:max_entries` (default `1024`) is exceeded, the oldest conversation is evicted.
  Entries live in memory only: after a restart the next compaction summarizes
  once and stores a new entry. Summaries can contain conversation content; size
  the store, and its process ownership, like any other in-memory cache of it.
  """

  use Agent

  @default_max 1024

  @doc "Start the store. Options: `:name`, `:max_entries` (positive integer)."
  def start_link(opts \\ []) do
    max = Keyword.get(opts, :max_entries, @default_max)

    unless is_integer(max) and max > 0,
      do: raise(ArgumentError, "expected :max_entries to be a positive integer")

    Agent.start_link(fn -> {max, %{}, :queue.new()} end, Keyword.take(opts, [:name]))
  end

  @doc false
  # Never raises: an unavailable store means "no stored summary".
  def fetch(memo, key) do
    Agent.get(memo, fn {_max, entries, _order} -> Map.get(entries, key) end)
  catch
    :exit, _ -> nil
  end

  @doc false
  def store(memo, key, value) do
    Agent.update(memo, fn {max, entries, order} ->
      order = if Map.has_key?(entries, key), do: order, else: :queue.in(key, order)
      evict(max, Map.put(entries, key, value), order)
    end)
  catch
    :exit, _ -> :ok
  end

  @doc "Number of stored conversations."
  def size(memo), do: Agent.get(memo, fn {_, entries, _} -> map_size(entries) end)

  defp evict(max, entries, order) when map_size(entries) <= max, do: {max, entries, order}

  defp evict(max, entries, order) do
    {{:value, oldest}, order} = :queue.out(order)
    evict(max, Map.delete(entries, oldest), order)
  end
end

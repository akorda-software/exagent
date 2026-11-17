defmodule ExAgent.Memory.ETS do
  @moduledoc """
  An in-memory `ExAgent.Memory` backend, per node.

  A GenServer owns a protected named ETS table: reads go straight to the table
  and writes are serialized through the owner, which checks the expected
  version. Contents are lost when the table's owner stops. The library starts a
  default table named `ExAgent.Memory.ETS` (`:ets` in `ExAgent.Memory.tool/2`);
  start more under your own supervisor:

      children = [{ExAgent.Memory.ETS, name: MyApp.Memory}]

      ExAgent.Memory.tool({ExAgent.Memory.ETS, MyApp.Memory}, scope: "team:7")
  """

  @behaviour ExAgent.Memory
  use GenServer

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :name, __MODULE__)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @impl GenServer
  def init(name) do
    table = :ets.new(name, [:set, :protected, :named_table, read_concurrency: true])
    # Versions come from one table-wide counter, so a scope deleted and created
    # again never reuses a version a stale writer could still expect.
    {:ok, {table, 0}}
  end

  @impl ExAgent.Memory
  def validate(table) when is_atom(table) and not is_nil(table), do: :ok
  def validate(_), do: {:error, "the ETS memory config must be the table name"}

  @impl ExAgent.Memory
  def load(table, scope) do
    case :ets.lookup(table, scope) do
      [{^scope, version, files}] -> {:ok, version, files}
      [] -> {:ok, 0, %{}}
    end
  end

  @impl ExAgent.Memory
  def store(table, scope, expected, files) do
    GenServer.call(table, {:store, scope, expected, files})
  end

  @impl GenServer
  def handle_call({:store, scope, expected, files}, _from, {table, counter} = state) do
    current =
      case :ets.lookup(table, scope) do
        [{^scope, version, _}] -> version
        [] -> 0
      end

    cond do
      current != expected ->
        {:reply, {:error, :conflict}, state}

      files == %{} ->
        :ets.delete(table, scope)
        {:reply, {:ok, 0}, state}

      true ->
        :ets.insert(table, {scope, counter + 1, files})
        {:reply, {:ok, counter + 1}, {table, counter + 1}}
    end
  end
end

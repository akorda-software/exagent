defmodule ExAgent.Memory.Postgres do
  @moduledoc """
  A durable `ExAgent.Memory` backend on PostgreSQL, through the host's
  `Ecto.Repo` (add `ecto_sql` and `postgrex` to your app, as for
  `ExAgent.Store.Postgres`).

      # once, from a migration or at boot:
      :ok = ExAgent.Memory.Postgres.migrate(MyApp.Repo)

      ExAgent.Memory.tool({ExAgent.Memory.Postgres, MyApp.Repo}, scope: "user:42")

  Each scope is one row: `scope` (primary key), `version`, `data` (the files as
  JSON text) and `updated_at`. Versions come from a sequence, so they are never
  reused, and every write is a single conditional statement. The table is
  `exagent_memory` by default; choose another with
  `{ExAgent.Memory.Postgres, {MyApp.Repo, table: "agent_memory"}}` (at most 48
  characters, letters, digits and underscores) and create it with
  `migrate(MyApp.Repo, "agent_memory")`.
  """

  @behaviour ExAgent.Memory

  @default_table "exagent_memory"

  @doc """
  Create the memory table and its version sequence (idempotent).
  """
  @spec migrate(module(), String.t()) :: :ok | {:error, term()}
  def migrate(repo, table \\ @default_table) do
    {table, sequence} = names!(table)

    with {:ok, _} <- repo.query("CREATE SEQUENCE IF NOT EXISTS #{sequence}", []),
         {:ok, _} <-
           repo.query(
             "CREATE TABLE IF NOT EXISTS #{table} (scope text PRIMARY KEY, " <>
               "version bigint NOT NULL, data text NOT NULL, " <>
               "updated_at timestamptz NOT NULL DEFAULT now())",
             []
           ) do
      :ok
    end
  end

  @impl true
  def validate(config) do
    conf(config)
    :ok
  rescue
    error in [ArgumentError, FunctionClauseError] -> {:error, Exception.message(error)}
  end

  @impl true
  def load(config, scope) do
    {repo, table, _} = conf(config)

    case repo.query("SELECT version, data FROM #{table} WHERE scope = $1", [scope]) do
      {:ok, %{rows: []}} -> {:ok, 0, %{}}
      {:ok, %{rows: [[version, data]]}} -> decode(version, data)
      {:error, _} = error -> error
    end
  end

  defp decode(version, data) do
    case Jason.decode(data) do
      {:ok, files} when is_map(files) -> {:ok, version, files}
      _ -> {:error, :invalid_memory_record}
    end
  end

  @impl true
  def store(config, scope, expected, files) do
    {repo, table, sequence} = conf(config)
    next = "nextval('#{sequence}')"

    {sql, params} =
      cond do
        files == %{} and expected == 0 ->
          {"SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM #{table} WHERE scope = $1)", [scope]}

        files == %{} ->
          {"DELETE FROM #{table} WHERE scope = $1 AND version = $2 RETURNING 0",
           [scope, expected]}

        expected == 0 ->
          {"INSERT INTO #{table} (scope, version, data) VALUES ($1, #{next}, $2) " <>
             "ON CONFLICT (scope) DO NOTHING RETURNING version", [scope, Jason.encode!(files)]}

        true ->
          {"UPDATE #{table} SET version = #{next}, data = $3, updated_at = now() " <>
             "WHERE scope = $1 AND version = $2 RETURNING version",
           [scope, expected, Jason.encode!(files)]}
      end

    case repo.query(sql, params) do
      {:ok, %{rows: [[version]]}} -> {:ok, version}
      {:ok, %{rows: []}} -> {:error, :conflict}
      {:error, _} = error -> error
    end
  end

  defp conf(repo) when is_atom(repo), do: Tuple.insert_at(names!(@default_table), 0, repo)

  defp conf({repo, opts}) when is_atom(repo) and is_list(opts),
    do: Tuple.insert_at(names!(opts[:table] || @default_table), 0, repo)

  defp names!(name) when is_binary(name) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]{0,47}\z/, name),
      do: {~s("#{name}"), ~s("#{name}_version_seq")},
      else: raise(ArgumentError, "invalid memory table identifier")
  end
end

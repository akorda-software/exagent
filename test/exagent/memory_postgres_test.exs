defmodule ExAgent.MemoryPostgresTest do
  use ExUnit.Case, async: false

  # Skipped with the rest of :postgres when no database is available.
  @moduletag :postgres

  alias ExAgent.Memory
  alias ExAgent.Memory.Postgres

  @repo ExAgent.TestRepo
  @memory {Postgres, @repo}

  setup_all do
    :ok = Postgres.migrate(@repo)
    # Idempotent.
    :ok = Postgres.migrate(@repo)
    :ok
  end

  setup do
    scope = "pg-#{System.unique_integer([:positive])}"
    on_exit(fn -> Memory.clear(@memory, scope) end)
    {:ok, scope: scope}
  end

  test "compare-and-swap, delete and versions that are never reused", %{scope: scope} do
    assert {:ok, 0, %{}} = Postgres.load(@repo, scope)
    assert {:ok, 0} = Postgres.store(@repo, scope, 0, %{})
    assert {:ok, v1} = Postgres.store(@repo, scope, 0, %{"/memories/a" => "1"})
    assert {:error, :conflict} = Postgres.store(@repo, scope, 0, %{"/memories/a" => "x"})
    assert {:error, :conflict} = Postgres.store(@repo, scope, 0, %{})
    assert {:ok, v2} = Postgres.store(@repo, scope, v1, %{"/memories/a" => "2"})
    assert {:error, :conflict} = Postgres.store(@repo, scope, v1, %{"/memories/a" => "stale"})
    assert {:ok, 0} = Postgres.store(@repo, scope, v2, %{})
    assert {:ok, v3} = Postgres.store(@repo, scope, 0, %{"/memories/a" => "3"})
    assert v3 not in [v1, v2]
    assert {:error, :conflict} = Postgres.store(@repo, scope, v1, %{"/memories/a" => "stale"})
    assert {:ok, ^v3, %{"/memories/a" => "3"}} = Postgres.load(@repo, scope)
  end

  test "the tool works end to end and keeps concurrent edits", %{scope: scope} do
    tool = Memory.tool(@memory, scope: scope)
    ctx = %ExAgent.RunContext{}

    assert {:ok, _} =
             tool.call.(ctx, %{
               "command" => "create",
               "path" => "/memories/notes.md",
               "file_text" => "ünïcode ✓\n"
             })

    results =
      1..10
      |> Task.async_stream(
        fn n ->
          tool.call.(ctx, %{
            "command" => "create",
            "path" => "/memories/n#{n}",
            "file_text" => "x"
          })
        end,
        max_concurrency: 10
      )
      |> Enum.map(fn {:ok, result} -> result end)

    {:ok, files} = Memory.files(@memory, scope)
    assert files["/memories/notes.md"] == "ünïcode ✓\n"
    assert map_size(files) - 1 == Enum.count(results, &match?({:ok, _}, &1))
  end

  test "custom table names are validated" do
    assert_raise ArgumentError, fn -> Postgres.migrate(@repo, "bad name") end

    assert_raise ArgumentError, fn ->
      Postgres.load({@repo, table: String.duplicate("a", 49)}, "s")
    end

    assert :ok = Postgres.migrate(@repo, "exagent_memory_custom")
    assert {:ok, 0, %{}} = Postgres.load({@repo, table: "exagent_memory_custom"}, "s")
  end
end

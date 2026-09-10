defmodule ExAgent.StoreRepoContractTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Store, Server.Snapshot}
  alias ExAgent.Message.Usage

  # Script only the Repo result; the real Postgres adapter constructs SQL, keys
  # and JSON before reaching this boundary. Each test owns its process dictionary.
  defmodule Repo do
    def query(sql, params) do
      send(self(), {:repo_query, sql, params})

      case Process.get({__MODULE__, :reply}, {:ok, %{rows: []}}) do
        :raise -> raise "synthetic Repo exception"
        :throw -> throw(:synthetic_repo_throw)
        :exit -> exit(:synthetic_repo_exit)
        reply -> reply
      end
    end
  end

  @store {Store.Postgres, {Repo, table: "synthetic_snapshots"}}

  test "Postgres uses parameterized identity and actual portable bytes through the Repo boundary" do
    history = ExAgent.Test.TestingAuditRuntime.history()

    snapshot =
      Snapshot.new(
        agent_id: "customer-'quoted'",
        history: history,
        usage: %Usage{input_tokens: 8, output_tokens: 6, details: %{"cached_tokens" => 1}},
        metadata: %{"region" => "north"},
        revision: 7
      )

    assert :ok = Store.save_agent_snapshot(@store, snapshot)
    assert_receive {:repo_query, sql, ["agent:customer-'quoted'", bytes]}

    assert sql ==
             "INSERT INTO synthetic_snapshots (key, data) VALUES ($1, $2) " <>
               "ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data, updated_at = now()"

    refute sql =~ "customer"
    raw = Jason.decode!(bytes)
    assert raw["agent_id"] == "customer-'quoted'"
    assert raw["revision"] == 7

    assert raw["usage"] == %{
             "input_tokens" => 8,
             "output_tokens" => 6,
             "details" => %{"cached_tokens" => 1}
           }

    assert raw["metadata"] == %{"region" => "north"}

    assert Enum.at(Jason.decode!(raw["message_history"]), 2)["parts"] == [
             %{
               "__type__" => "tool_return",
               "tool_name" => "lookup",
               "tool_call_id" => "lookup-17",
               "status" => "succeeded",
               "content" => %{"record" => 17, "values" => [2, 7], "note" => "café"}
             }
           ]

    Process.put({Repo, :reply}, {:ok, %{rows: [[bytes]]}})
    assert {:ok, loaded} = Store.load_agent_snapshot(@store, snapshot.agent_id)

    assert_receive {:repo_query, "SELECT data FROM synthetic_snapshots WHERE key = $1",
                    ["agent:customer-'quoted'"]}

    assert loaded == snapshot
    assert {:ok, ^history} = Snapshot.messages(loaded)
    refute_received {:repo_query, _, _}
  end

  test "strict serialization rejects opaque data before Repo IO and dispatcher contains the exception" do
    bad = Snapshot.new(agent_id: "opaque", history: [], metadata: %{callback: fn -> :secret end})

    assert_raise Protocol.UndefinedError, fn ->
      Store.Postgres.save_agent_snapshot({Repo, table: "synthetic_snapshots"}, bad)
    end

    refute_received {:repo_query, _, _}

    assert {:error, {:exception, %Protocol.UndefinedError{}}} =
             Store.save_agent_snapshot(@store, bad)

    refute_received {:repo_query, _, _}
  end

  test "save and load propagate Repo errors, raises, throws and exits without IO replay" do
    snapshot = Snapshot.new(agent_id: "failure", history: [])

    for operation <- [:save, :load],
        mode <- [{:error, :synthetic_unavailable}, :raise, :throw, :exit] do
      Process.put({Repo, :reply}, mode)

      result =
        case operation do
          :save -> Store.save_agent_snapshot(@store, snapshot)
          :load -> Store.load_agent_snapshot(@store, "failure")
        end

      case mode do
        {:error, reason} ->
          assert result == {:error, reason}

        :raise ->
          assert {:error, {:exception, %RuntimeError{message: "synthetic Repo exception"}}} =
                   result

        :throw ->
          assert result == {:error, {:throw, :synthetic_repo_throw}}

        :exit ->
          assert result == {:error, {:exit, :synthetic_repo_exit}}
      end

      assert_receive {:repo_query, _, _}
      refute_received {:repo_query, _, _}
    end
  end
end

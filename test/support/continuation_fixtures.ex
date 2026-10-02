defmodule ExAgent.Test.ContinuationFixtures do
  @moduledoc false
  alias ExAgent.Continuation.{Record, Transition}
  alias ExAgent.Server.Snapshot

  def key, do: {"tenant-a", :agent, "conversation"}

  def snapshot(id \\ "conversation"),
    do:
      Snapshot.new(agent_id: id, history: [], revision: 7)
      |> Map.put(:saved_at, DateTime.from_unix!(0))
      |> Record.snapshot_data()

  def execution do
    %{
      "continuation_id" => "continuation-1",
      "run_id" => "run-1",
      "request_id" => "request-1",
      "definition" => %{"id" => "agent", "version" => "1"},
      "policy" => %{"id" => "policy", "version" => "1"},
      "model_ref" => %{"id" => "model", "version" => "1"},
      "deadline_at" => nil,
      "expires_at" => nil,
      "progress" => %{"active_elapsed_ms" => 50, "admissions" => ["model-1"]}
    }
  end

  def command(operation, payload \\ %{}, id \\ nil),
    do: %{
      "record_id" => "record-1",
      "operation" => operation,
      "operation_id" => id || operation,
      "actor_id" => "host-actor",
      "payload" => payload
    }

  def create(id \\ "conversation"),
    do: command("create", %{"snapshot" => snapshot(id), "execution" => execution()})

  def claim(until \\ 2_000, attempt \\ "attempt-1"),
    do:
      command(
        "claim",
        %{"owner_id" => "worker", "attempt_id" => attempt, "lease_until" => until},
        "claim-#{attempt}"
      )

  def worker(record, payload),
    do: Map.merge(Map.take(record["execution"], ~w(owner_id attempt_id fence)), payload)

  def intent,
    do: %{
      "kind" => "tool",
      "call_id" => "call-1",
      "payload" => %{"tool" => "charge", "arguments" => %{"amount" => 3}}
    }

  def begin_effect(record),
    do:
      command("begin_effect", worker(record, %{"effect_id" => "effect-1", "intent" => intent()}))

  def outcome(record, status \\ "succeeded"),
    do:
      command(
        "outcome",
        worker(record, %{
          "effect_id" => "effect-1",
          "outcome" => %{"status" => status, "data" => %{"receipt" => "external-1"}},
          "snapshot" => record["snapshot"],
          "progress" => record["execution"]["progress"]
        })
      )

  def ready do
    {:ok, %{record: record}} = Transition.apply(nil, key(), :absent, create(), 1_000)
    record
  end

  def claimed do
    record = ready()
    {:ok, %{record: record}} = Transition.apply(record, key(), 1, claim(), 1_001)
    record
  end
end

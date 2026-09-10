defmodule ExAgent.Server.SnapshotTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request, Usage}
  alias ExAgent.Server.Snapshot

  # Independently authored data exercises every conversation part in this fixture.
  defp sample_history, do: ExAgent.Test.TestingAuditRuntime.history()

  describe "new/1" do
    test "builds a snapshot with serialized history and mapped usage" do
      history = sample_history()

      snap =
        Snapshot.new(
          agent_id: "agent_x",
          history: history,
          usage: %Usage{input_tokens: 3, output_tokens: 4},
          metadata: %{room: "tavern"}
        )

      assert snap.agent_id == "agent_x"
      assert %DateTime{} = snap.saved_at
      # message_history is a JSON binary (the serialized conversation)
      assert is_binary(snap.message_history)
      assert String.contains?(snap.message_history, "be concise")
      assert snap.usage == %{"input_tokens" => 3, "output_tokens" => 4, "details" => %{}}
    end
  end

  describe "serialize/deserialize round-trip" do
    test "round-trips a snapshot through JSON" do
      history = sample_history()

      snap =
        Snapshot.new(
          agent_id: "rt",
          history: history,
          usage: %Usage{input_tokens: 5, output_tokens: 6},
          metadata: %{k: "v"}
        )

      binary = Snapshot.serialize(snap)
      assert {:ok, %Snapshot{} = restored} = Snapshot.deserialize(binary)

      assert restored.agent_id == "rt"
      assert restored.usage == %{"input_tokens" => 5, "output_tokens" => 6, "details" => %{}}
      assert restored.metadata == %{"k" => "v"}
      assert restored == %{snap | metadata: %{"k" => "v"}}
      assert {:ok, ^history} = Snapshot.messages(restored)
    end

    test "messages/1 reconstructs Message structs after a round-trip" do
      history = sample_history()

      snap = Snapshot.new(agent_id: "rt2", history: history, usage: nil)

      {:ok, restored} = snap |> Snapshot.serialize() |> Snapshot.deserialize()
      {:ok, messages} = Snapshot.messages(restored)

      assert messages == history

      # The first request still carries the system instruction + user prompt.
      [%Request{parts: parts} | _] = messages
      assert Enum.any?(parts, &match?(%Part.System{}, &1))
      assert Enum.any?(parts, &match?(%Part.User{content: "hi"}, &1))
    end

    test "usage_struct/1 rebuilds a Usage struct" do
      usage = %Usage{input_tokens: 7, output_tokens: 9, details: %{"cached_tokens" => 3}}
      snap = Snapshot.new(agent_id: "u", history: [], usage: usage)

      {:ok, restored} = snap |> Snapshot.serialize() |> Snapshot.deserialize()

      assert Snapshot.usage_struct(restored) == usage
    end

    test "messages/1 on an empty snapshot yields []" do
      snap = %Snapshot{agent_id: "x", message_history: nil}
      assert {:ok, []} = Snapshot.messages(snap)
    end
  end

  describe "serialization refuses opaque runtime values, without redacting application strings" do
    test "serialize/1 raises when metadata contains a function capture" do
      snap = Snapshot.new(agent_id: "bad", history: [], metadata: %{leak: fn -> :ok end})
      assert refuses_to_serialize?(snap)
    end

    test "serialize/1 raises when metadata contains a pid" do
      snap = Snapshot.new(agent_id: "bad", history: [], metadata: %{pid: self()})
      assert refuses_to_serialize?(snap)
    end

    test "snapshot has no live model/tools fields and preserves explicit application strings" do
      # The Snapshot struct has no fields for tools/model/api_key — only
      # conversational state. This is a static guarantee, asserted here.
      fields = Snapshot.__struct__() |> Map.from_struct() |> Map.keys()

      refute :tools in fields
      refute :model in fields
      refute :api_key in fields

      sentinel = "SYNTHETIC_APPLICATION_STRING"

      snapshot =
        Snapshot.new(
          agent_id: "strings",
          history: [],
          metadata: %{"api_key" => sentinel},
          provider_state: %{"note" => sentinel}
        )

      assert {:ok, restored} = Snapshot.deserialize(Snapshot.serialize(snapshot))
      assert restored.metadata == %{"api_key" => sentinel}
      assert restored.provider_state == %{"note" => sentinel}
    end
  end

  describe "versioned data validation" do
    test "history roots and parts form a Request/Response protocol tree" do
      user = %{"__type__" => "user", "content" => "hello"}
      text = %{"__type__" => "text", "content" => "orphan"}
      request = %{"__type__" => "request", "parts" => [user]}
      response = %{"__type__" => "response", "parts" => [text]}

      invalid = [
        [nil],
        [text],
        [%{request | "parts" => [nil]}],
        [%{response | "parts" => [nil]}],
        [%{request | "parts" => [response]}],
        [%{response | "parts" => [request]}],
        [%{request | "parts" => [text]}],
        [%{response | "parts" => [user]}],
        [Map.put(response, "usage", request)]
      ]

      for version <- [1, 2], history <- invalid do
        snapshot = %Snapshot{
          agent_id: "bad-tree",
          version: version,
          message_history: Jason.encode!(history)
        }

        assert {:error, :invalid_history} = Snapshot.messages(snapshot)
        assert {:error, :invalid_history} = Snapshot.deserialize(Snapshot.serialize(snapshot))
        assert {:error, :invalid_history} = Snapshot.validate(snapshot, "bad-tree")
      end
    end

    test "protocol-looking JSON inside User/ToolReturn remains opaque application data" do
      data = %{"__type__" => "request", "parts" => [nil]}

      history = [
        ExAgent.Message.new_request([
          %Part.User{content: [data]},
          %Part.ToolReturn{tool_name: "fetch", tool_call_id: "call", content: data}
        ])
      ]

      snapshot = Snapshot.new(agent_id: "opaque", history: history)
      assert {:ok, restored} = Snapshot.deserialize(Snapshot.serialize(snapshot))
      assert {:ok, [%Request{parts: [user, tool_return]}]} = Snapshot.messages(restored)
      assert user.content == [data]
      assert tool_return.content == data
    end

    test "valid v1 usage/history migrates to v2 without losing details" do
      json =
        Jason.encode!(%{
          version: 1,
          agent_id: "legacy",
          message_history: "[]",
          usage: %{input_tokens: 4, output_tokens: 2, details: %{cached_tokens: 3}}
        })

      assert {:ok, %Snapshot{version: 2, revision: 0} = snapshot} = Snapshot.deserialize(json)
      assert Snapshot.usage_struct(snapshot).details == %{"cached_tokens" => 3}
      assert {:error, :snapshot_id_mismatch} = Snapshot.validate(snapshot, "other")
    end

    test "future/corrupt payloads return errors, not exceptions or empty state" do
      for payload <- [
            "[]",
            "null",
            "{",
            ~s({"version":999}),
            ~s({"agent_id":"a","usage":{"input_tokens":-1}}),
            ~s({"agent_id":"a","message_history":"{}"}),
            ~s({"agent_id":"a","saved_at":"not-a-date"}),
            ~s({"agent_id":"a","metadata":42})
          ] do
        assert {:error, _} = Snapshot.deserialize(payload)
      end
    end
  end

  # Strict JSON serialization must fail (raise) for non-encodable values. We
  # don't pin the exact exception type (Jason raises Protocol.UndefinedError
  # today); we only assert it refuses to serialize.
  defp refuses_to_serialize?(snap) do
    try do
      Snapshot.serialize(snap)
      false
    rescue
      _ -> true
    end
  end
end

defmodule ExAgent.Frame10FatalCapacityFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias ExAgent.{Message, Store}
  alias ExAgent.Continuation.{Authority, Budget, Frame, Record, RequestData, StructuralSnapshot}
  alias ExAgent.Message.Part

  # Only command inputs are synthetic. Records are produced exclusively by Store
  # transitions, and every successful acknowledgement is encoded and decoded.
  def ref, do: %{"id" => "operations", "version" => "1"}

  def tools do
    config = %{
      definition: ref(),
      policy: ref(),
      model_ref: ref(),
      model_codec: %{
        dump: fn _ -> raise "no codec" end,
        load: fn _, _ -> raise "no codec" end
      }
    }

    delegate =
      ExAgent.Coordination.delegation_tool(ExAgent.new(model: %ExAgent.Models.Test{}),
        name: "delegate",
        prompt_arg: "task",
        continuation: config
      )

    plain =
      ExAgent.Tool.new(
        name: "plain",
        description: "plain",
        takes_ctx: false,
        parameters_json_schema: %{"type" => "object"},
        call: fn _ -> raise "no worker" end
      )

    [delegate, plain]
  end

  def create do
    step = %{
      id: "B",
      agent: ExAgent.new(model: %ExAgent.Models.Test{}),
      definition: ref(),
      policy: ref(),
      model_ref: ref(),
      output_ref: ref(),
      model_codec: %{dump: fn _ -> raise "no codec" end, load: fn _, _ -> raise "no codec" end}
    }

    {:ok, definition} =
      ExAgent.Coordination.Composition.new(id: "operations", version: "1", steps: [step])

    {:ok, binding} = ExAgent.Coordination.Composition.binding(definition)

    root = %{
      "frame_version" => 10,
      "kind" => "sequence",
      "cursor" => "empty",
      "run_id" => "root",
      "binding" => binding,
      "input" => "root input",
      "children" => %{},
      "tool_batches" => %{},
      "output_resolutions" => %{},
      "authority" => %{
        "root" =>
          Map.merge(authority(), %{
            "usage" => Authority.usage(%ExAgent.UsageLimits{}),
            "checkpoint_limit" => Process.get(:limit, Record.max_bytes())
          })
      },
      "scope" => %{
        "scope_version" => 2,
        "root_run_id" => "root",
        "nodes" => %{
          "root" => %{"parent_run_id" => nil, "requests" => 0, "tools" => 0}
        },
        "operations" => [],
        "batches" => [],
        "retry_batches" => []
      },
      "frontier" => %{"epoch" => 0, "state" => "open", "reason" => nil, "fatal" => nil}
    }

    command("create", %{
      "snapshot" => StructuralSnapshot.new("conversation", root),
      "execution" => %{
        "kind" => "composition",
        "continuation_id" => "continuation",
        "run_id" => "root",
        "definition" => ref(),
        "policy" => ref(),
        "deadline_at" => nil,
        "expires_at" => nil,
        "progress" => %{"runtime" => root, "active_budget" => Budget.new(60_000)}
      }
    })
  end

  def authority,
    do: %{
      "policies" => [%{"default" => "allow", "rules" => []}],
      "deadline_at" => nil,
      "max_concurrent_requests" => nil
    }

  def node(root, id, parent, link) do
    {:ok, inventory} = Frame.inventory(tools())

    {:ok, settings} =
      ExAgent.Tool.JSON.normalize(
        Map.from_struct(%ExAgent.ModelSettings{})
        |> Map.delete(:timeout)
      )

    params = %{output_mode: :text, allow_text_output: true, output_object: nil, output_tools: []}
    {:ok, fingerprint} = Frame.output_fingerprint(params)
    input = if link["kind"] == "step", do: link["input"], else: link["args"]["task"]

    leaf = %{
      "frame_version" => 3,
      "cursor" => "request",
      "run_id" => id,
      "first_new_message_index" => 0,
      "run_step" => 0,
      "model_request_id" => nil,
      "tool_retries" => %{},
      "output_retries_used" => 0,
      "tool_return_bytes" => 4096,
      "selected_tools" => inventory,
      "model_data" => nil,
      "model_binding" => nil,
      "settings" => settings,
      "limits" => %{"output_retries" => 1, "usage" => root["authority"]["root"]["usage"]},
      "permissions" => %{},
      "scope" => nil,
      "outcomes" => %{},
      "output_fingerprint" => fingerprint
    }

    snapshot =
      ExAgent.Server.Snapshot.new(
        agent_id: "conversation",
        history: [%Message.Request{run_id: id, parts: [%Part.User{content: input}]}]
      )
      |> Record.snapshot_data()

    %{
      "parent_run_id" => parent,
      "link" => link,
      "definition" => ref(),
      "policy" => ref(),
      "model_ref" => ref(),
      "output_ref" => if(link["kind"] == "step", do: ref()),
      "frame" => leaf,
      "snapshot" => snapshot,
      "status" => "running",
      "result" => nil,
      "result_omitted" => nil,
      "error" => nil
    }
  end

  def command(op, payload),
    do: %{
      "record_id" => "record",
      "operation" => op,
      "operation_id" => "operation-#{System.unique_integer([:positive])}",
      "actor_id" => "host",
      "payload" => payload
    }

  def claim(attempt \\ "attempt"),
    do:
      command("claim", %{
        "owner_id" => "owner",
        "attempt_id" => attempt,
        "lease_until" => System.system_time(:millisecond) + 600_000
      })

  def worker(r, op, payload \\ %{}) do
    e = r["execution"]

    command(
      op,
      Map.merge(payload, %{
        "owner_id" => e["owner_id"],
        "attempt_id" => e["attempt_id"],
        "fence" => e["fence"],
        "epoch" => root(r)["frontier"]["epoch"]
      })
    )
  end

  def commit(store, previous, cmd) do
    expected = if previous, do: previous["revision"], else: :absent
    n = if previous, do: previous["revision"] + 1, else: 1

    cmd = %{
      cmd
      | "operation_id" =>
          String.duplicate(<<1>>, 505) <> String.pad_leading(to_string(n), 7, "0"),
        "actor_id" => String.duplicate(<<2>>, 512)
    }

    result = Store.transition(store, :agent, "conversation", expected, cmd)

    if match?({:error, _}, result) do
      assert {:ok, ^previous} = Store.load_record(store, :agent, "conversation")
      throw({:rejected, cmd, result, previous})
    end

    assert {:ok, %{record: record, replayed: false}} = result
    assert Record.cleanup_reserve_bytes(record) >= 0
    assert Record.receipt_reserve(record["execution"]) >= 0

    for {id, receipt} <- record["receipts"] do
      assert byte_size(id) == 512
      assert byte_size(receipt["actor_id"]) == 512
    end

    cost = byte_size(Jason.encode!(record)) + Record.cleanup_reserve_bytes(record)
    Process.put(:rows, Process.get(:rows, []) ++ [{cmd, record, cost}])

    key = {store.namespace, :agent, "conversation"}
    assert {:ok, bytes} = Record.encode(record, key)
    assert {:ok, ^record} = Record.decode(bytes, key)
    assert {:ok, ^record} = Store.load_record(store, :agent, "conversation")
    record
  end

  def op(store, r, operation, payload \\ %{}), do: commit(store, r, worker(r, operation, payload))
  def root(r), do: r["execution"]["progress"]["runtime"]

  def target(run, request, call \\ nil),
    do:
      Map.merge(
        %{"run_id" => run, "request_id" => request},
        if(call, do: %{"call_id" => call}, else: %{})
      )

  def model(store, r, run, request, calls, admit_batch? \\ true, usage \\ nil) do
    root = root(r)
    node = root["children"][run]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(tools(), &{&1.name, &1}),
      settings: %ExAgent.ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: %{
        output_mode: :text,
        allow_text_output: true,
        output_object: nil,
        output_tools: [],
        instructions: []
      }
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: ref()}, root)
    r = op(store, r, "begin_effect", Map.put(target(run, request), "request_data", data))

    r =
      op(
        store,
        r,
        "outcome",
        Map.merge(target(run, request), %{
          "response" => Message.to_json([%Message.Response{parts: calls, usage: usage}]),
          "model_data" => nil
        })
      )

    if admit_batch? and Enum.any?(calls, &match?(%Part.ToolCall{}, &1)),
      do: op(store, r, "batch_begin", target(run, request)),
      else: r
  end

  def started(store) do
    r = commit(store, nil, create())
    r = commit(store, r, claim())

    n =
      node(root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    op(store, r, "step_input", %{"node_id" => "B", "node" => n, "authority" => authority()})
  end

  def attached(store, r) do
    args = %{"task" => "D input", "prompt" => "wrong input"}
    target = target("B", "request-B", "delegate")
    r = model(store, r, "B", "request-B", [call("delegate", "delegate", args)])
    r = prepare(store, r, target, args)

    binding =
      root(r)["tool_batches"][ExAgent.Continuation.ToolEvidence.key("B", "request-B")]["calls"][
        "delegate"
      ]["binding"]

    link =
      Map.merge(binding, %{
        "kind" => "delegate",
        "parent_request_id" => "request-B",
        "call_id" => "delegate"
      })

    n = node(root(r), "D", "B", link)
    payload = Map.merge(target, %{"node_id" => "D", "node" => n, "authority" => authority()})
    {r, payload}
  end

  def awaiting_pause(store) do
    {r, attach} = attached(store, started(store))

    attach =
      update_in(
        attach,
        ["authority", "policies"],
        &(&1 ++ [%{"default" => "ask", "rules" => []}])
      )

    r = op(store, r, "node_attach", attach)
    r = model(store, r, "D", "request-D", [call("plain", "one"), call("plain", "two")])
    r = prepare(store, r, target("D", "request-D", "one"), %{})
    r = prepare(store, r, target("D", "request-D", "two"), %{})
    r = op(store, r, "call_wait", target("D", "request-D", "one"))
    r = op(store, r, "call_wait", target("D", "request-D", "two"))
    r = op(store, r, "node_suspend", %{"node_id" => "D"})
    op(store, r, "node_suspend", %{"node_id" => "B"})
  end

  def prepare(store, r, target, args) do
    r = op(store, r, "call_prepare", target)
    op(store, r, "call_prepared", Map.put(target, "args", args))
  end

  def call(name, id, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args, kind: :function}

  def settled(store, r, target, content \\ "raw", usage \\ nil) do
    r = prepare(store, r, target, %{})
    r = op(store, r, "begin_effect", target)

    bytes =
      ExAgent.Continuation.Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: target["call_id"],
        content: content,
        status: :succeeded
      })

    result =
      Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

    raw =
      if is_nil(usage), do: result, else: Map.put(result, "usage", Message.Usage.to_map(usage))

    r = op(store, r, "outcome", raw)
    r = op(store, r, "call_wrap", target)
    op(store, r, "call_settle", result)
  end
end

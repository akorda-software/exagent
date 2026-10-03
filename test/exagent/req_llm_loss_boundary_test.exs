defmodule ExAgent.ReqLLMLossBoundaryTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Tool}

  @specification %{
    provider: :openai,
    id: "loss-boundary",
    capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
    extra: %{wire: %{protocol: "openai_chat"}}
  }

  test "stock lost siblings are distinct from visible invalid calls and never expand tool authority" do
    valid = %{
      "id" => "valid",
      "type" => "function",
      "function" => %{"name" => "effect", "arguments" => ~s|{"arguments":{}}|}
    }

    invalid = fn args -> put_in(%{valid | "id" => "invalid"}, ["function", "arguments"], args) end

    observations =
      for {label, sibling, visible?, denied?} <- [
            {:positive, :none, false, false},
            {:lost_id_only, %{"id" => "incomplete"}, false, false},
            {:lost_null, nil, false, false},
            {:lost_name_only, %{"function" => %{"name" => "effect"}}, false, false},
            {:truncated_visible, invalid.("{"), true, false},
            {:missing_envelope_visible, invalid.("{}"), true, false},
            {:schema_invalid_visible, invalid.(~s|{"arguments":{"extra":1}}|), true, false},
            {:lost_but_denied, %{"id" => "incomplete"}, false, true}
          ] do
        calls = if sibling == :none, do: [valid], else: [valid, sibling]
        url = peer(calls, if(visible?, do: 2, else: 3))

        {:ok, public} =
          ReqLLM.generate_text(@specification, "go",
            api_key: "synthetic",
            base_url: url,
            max_retries: 0,
            json_repair: false
          )

        exposed = %{
          calls: ReqLLM.Response.tool_calls(public),
          error: public.error,
          provider_meta: public.provider_meta,
          message_metadata: public.message.metadata,
          call_metadata: ReqLLM.Response.call_metadata(public)
        }

        assert length(exposed.calls) == if(visible?, do: 2, else: 1)
        assert public.error == nil
        effects = :atomics.new(1, [])

        tool =
          Tool.new(
            name: "effect",
            takes_ctx: false,
            parameters_json_schema: %{
              "type" => "object",
              "properties" => %{},
              "additionalProperties" => false
            },
            call: fn _ ->
              :atomics.add(effects, 1, 1)
              "saved"
            end
          )

        model =
          ExAgent.Models.ReqLLM.new(
            model: @specification,
            api_key: "synthetic",
            base_url: url,
            tool_profile: :chat_tools_v1
          )

        options =
          if denied?, do: [permissions: ExAgent.Permissions.new!(rules: [{"*", :deny}])], else: []

        result = ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go", options)
        actual_effects = :atomics.get(effects, 1)

        if visible? do
          assert {:error, %ExAgent.RunError{partial: partial}} = result
          assert partial.request_count == 1
          assert partial.tool_calls == 0
          assert actual_effects == 0
        else
          assert {:ok, final} = result
          assert final.output == "done"
          assert final.request_count == 2
          assert final.tool_calls == 1

          returns =
            for %Message.Request{parts: parts} <- final.messages,
                %Message.Part.ToolReturn{} = part <- parts,
                do: part

          assert [return] = returns
          assert return.tool_call_id == "valid"
          assert return.status == if(denied?, do: :denied, else: :succeeded)
          assert actual_effects == if(denied?, do: 0, else: 1)
        end

        {label, exposed, elem(result, 0), actual_effects}
      end

    [{:positive, baseline, :ok, 1} | rest] = observations

    for {label, exposed, _, _} <- rest,
        label in [:lost_id_only, :lost_null, :lost_name_only, :lost_but_denied],
        do: assert(exposed == baseline)

    IO.inspect(
      Enum.map(observations, fn {label, _, status, effects} -> {label, status, effects} end),
      label: "R18_PUBLIC_LOSS_BOUNDARY"
    )

    assert Enum.map(observations, fn {label, _, status, effects} -> {label, status, effects} end) ==
             [
               {:positive, :ok, 1},
               {:lost_id_only, :ok, 1},
               {:lost_null, :ok, 1},
               {:lost_name_only, :ok, 1},
               {:truncated_visible, :error, 0},
               {:missing_envelope_visible, :error, 0},
               {:schema_invalid_visible, :error, 0},
               {:lost_but_denied, :ok, 0}
             ]
  end

  defp peer(calls, requests) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn_link(fn ->
        for _ <- 1..requests do
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          body = receive_request(socket, "")
          final? = Enum.any?(body["messages"], &(&1["role"] == "assistant"))

          message =
            if final?,
              do: %{"role" => "assistant", "content" => "done"},
              else: %{"role" => "assistant", "content" => nil, "tool_calls" => calls}

          response =
            Jason.encode!(%{
              "id" => "loss",
              "model" => "loss-boundary",
              "choices" => [
                %{
                  "index" => 0,
                  "message" => message,
                  "finish_reason" => if(final?, do: "stop", else: "tool_calls")
                }
              ]
            })

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(response)}\r\nConnection: close\r\n\r\n" <>
                response
            )

          :gen_tcp.close(socket)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}/v1"
  end

  defp receive_request(socket, bytes) do
    case String.split(bytes, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, headers)

        if byte_size(body) >= String.to_integer(size),
          do: Jason.decode!(body),
          else: more(socket, bytes)

      _ ->
        more(socket, bytes)
    end
  end

  defp more(socket, bytes) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    receive_request(socket, bytes <> chunk)
  end
end

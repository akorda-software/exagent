defmodule ExAgent.ReqLLMTimeoutTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Model, ModelSettings, ModelRequestParameters, RequestError}
  alias ExAgent.Models.ReqLLM, as: Adapter

  @model %{provider: :openai, id: "timeout-fixture"}
  defp body,
    do:
      Jason.encode!(%{
        "id" => "timeout",
        "model" => "timeout-fixture",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{"role" => "assistant", "content" => "ok"},
            "finish_reason" => "stop"
          }
        ]
      })

  defp request(url, timeout),
    do:
      Model.request(
        Adapter.new(model: @model, api_key: "synthetic", base_url: url),
        [Message.new_request([%Message.Part.User{content: "synthetic"}])],
        %ModelSettings{timeout: timeout},
        %ModelRequestParameters{}
      )

  test "real503 and redirect307 each perform exactly one request without following redirect" do
    for status <- [503, 307] do
      {url, count, _} =
        peer(fn socket, port ->
          reply(socket, status, body(), "Location: http://127.0.0.1:#{port}/redirect\r\n")
        end)

      assert {:error, %RequestError{status: ^status}} = request(url, 500)
      assert Agent.get(count, & &1) == 1
    end
  end

  test "receive inactivity times out on actual HTTP while the server withholds headers" do
    parent = self()

    {url, count, _} =
      peer(fn socket, _ ->
        send(parent, {:withholding, self()})

        receive do
          :release -> reply(socket, 200, body())
        after
          2000 -> :ok
        end
      end)

    started = System.monotonic_time(:millisecond)
    caller = Task.async(fn -> request(url, 40) end)
    assert_receive {:withholding, server}, 1000
    assert {:error, %RequestError{}} = Task.await(caller, 1500)

    IO.inspect(%{receive_timeout: 40, elapsed_ms: System.monotonic_time(:millisecond) - started},
      label: "R16_RECEIVE"
    )

    assert Agent.get(count, & &1) == 1
    send(server, :release)
  end

  @tag :req_llm_characterization
  test "public total budget cancels this owned blocked callback without claiming generic effect rollback" do
    parent = self()

    transport = fn req ->
      send(parent, {:callback, self()})

      receive do
        :release -> :ok
      after
        1500 -> raise "callback probe watchdog"
      end

      send(parent, :callback_completed)

      {req,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: body()
       )}
    end

    started = System.monotonic_time(:millisecond)

    caller =
      Task.async(fn ->
        ReqLLM.generate_text(@model, "synthetic",
          api_key: "synthetic",
          base_url: "http://127.0.0.1:1/v1",
          max_retries: 0,
          total_timeout: 300,
          receive_timeout: 500,
          req_http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        )
      end)

    assert_receive {:callback, worker}, 1000
    monitor = Process.monitor(worker)
    assert {:error, error} = result = Task.await(caller, 1500)
    assert error.kind == :total
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    refute_receive :callback_completed, 0

    IO.inspect(
      %{
        total_timeout: 300,
        elapsed_ms: System.monotonic_time(:millisecond) - started,
        result: elem(result, 0)
      },
      label: "R16_ARBITRARY_CALLBACK"
    )
  end

  test "adapter total budget bounds one real buffered operation with unknown failure usage and socket cleanup" do
    parent = self()

    {url, count, _} =
      peer(fn socket, _ ->
        send(parent, :total_request_accepted)
        send(parent, {:total_socket_result, :gen_tcp.recv(socket, 0, 1500)})
      end)

    model =
      Adapter.new(
        model: @model,
        api_key: "synthetic-total-secret",
        base_url: url,
        total_timeout: 100
      )

    agent = ExAgent.new(model: model, model_settings: [timeout: 1000])

    assert {:error,
            %ExAgent.RunError{
              reason: {:model_request_failed, %RequestError{reason: {:timeout, :total}}}
            } = error} =
             ExAgent.run(agent, "held")

    assert_receive :total_request_accepted
    assert_receive {:total_socket_result, {:error, :closed}}, 1500
    assert Agent.get(count, & &1) == 1
    assert error.partial.request_count == 1
    assert error.partial.usage_status == :partial
    assert error.partial.cost_status == :unknown
    refute inspect(error.reason) =~ "synthetic-total-secret"
  end

  test "qualified buffered tools never execute on partial HTTP followed by timeout or owner cancellation" do
    owner = self()

    for action <- [:timeout, :cancel] do
      {url, count, _} =
        peer(fn socket, _ ->
          # The call JSON is complete, but the HTTP body and enclosing response are not.
          call =
            Jason.encode!(%{
              "id" => "call-held",
              "type" => "function",
              "function" => %{"name" => "effect", "arguments" => "{\"arguments\":{}}"}
            })

          prefix = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"tool_calls\":[" <> call
          :ok = :gen_tcp.send(socket, headers(200, byte_size(prefix) + 100, "") <> prefix)
          send(owner, {:held_tool_response, self()})
          send(owner, {:held_tool_closed, action, :gen_tcp.recv(socket, 0, 1500)})
        end)

      spec = %{
        provider: :openai,
        id: "held-tool",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
      }

      model =
        Adapter.new(
          model: spec,
          tool_profile: :chat_tools_v1,
          api_key: "synthetic",
          base_url: url,
          total_timeout: if(action == :timeout, do: 300, else: 1000)
        )

      tool =
        ExAgent.Tool.new(
          name: "effect",
          parameters_json_schema: %{"type" => "object"},
          takes_ctx: false,
          call: fn _ -> send(owner, :held_tool_effect) end
        )

      task = Task.async(fn -> ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go") end)
      assert_receive {:held_tool_response, _}, 1000

      if action == :cancel do
        assert nil == Task.shutdown(task, :brutal_kill)
      else
        assert {:error, _} = Task.await(task, 1500)
      end

      assert_receive {:held_tool_closed, ^action, {:error, :closed}}, 1500
      assert Agent.get(count, & &1) == 1
      refute_receive :held_tool_effect, 0
    end
  end

  test "buffered guardian reaps its worker on success, exception and caller death" do
    owner = self()

    for outcome <- [:success, :exception, :cancel] do
      transport = fn request ->
        {:links, [guardian]} = Process.info(self(), :links)
        send(owner, {:owned_worker, self(), guardian})

        receive do
          :release -> :ok
        end

        if outcome == :exception, do: raise("synthetic-private-error")

        {request,
         Req.Response.new(
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: body()
         )}
      end

      model =
        Adapter.new(
          model: @model,
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        )

      task = Task.async(fn -> Model.request(model, [], nil, %ModelRequestParameters{}) end)
      assert_receive {:owned_worker, worker, guardian}, 1000
      worker_monitor = Process.monitor(worker)
      guardian_monitor = Process.monitor(guardian)

      case outcome do
        :cancel ->
          assert Task.shutdown(task, :brutal_kill) == nil

        :success ->
          send(worker, :release)
          assert {:ok, _, _} = Task.await(task)

        :exception ->
          send(worker, :release)
          assert {:error, error} = Task.await(task)
          refute inspect(error) =~ "synthetic-private-error"
      end

      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 1000
      assert_receive {:DOWN, ^guardian_monitor, :process, ^guardian, _}, 1000
    end
  end

  test "nil total timeout inherits the public application default without changing receive precedence" do
    previous = Application.fetch_env(:req_llm, :total_timeout)
    Application.put_env(:req_llm, :total_timeout, 80)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:req_llm, :total_timeout, value)
        :error -> Application.delete_env(:req_llm, :total_timeout)
      end
    end)

    owner = self()

    {url, count, _} =
      peer(fn socket, _ ->
        send(owner, :default_timeout_started)
        send(owner, {:default_timeout_closed, :gen_tcp.recv(socket, 0, 1500)})
      end)

    assert {:error, %RequestError{reason: {:timeout, :total}}} = request(url, 1000)
    assert_receive :default_timeout_started
    assert_receive {:default_timeout_closed, {:error, :closed}}, 1500
    assert Agent.get(count, & &1) == 1
  end

  test "queued completion after absolute deadline rejects effects, but timely completion may deliver later" do
    owner = self()

    for timely? <- [false, true] do
      count = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

      transport = fn req ->
        index = Agent.get_and_update(count, &{&1, &1 + 1})

        message =
          if index == 0 do
            {:links, [guardian]} = Process.info(self(), :links)
            send(owner, {:deadline_worker, self(), guardian})

            receive do
              :release -> :ok
            end

            %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "deadline-call",
                  "type" => "function",
                  "function" => %{"name" => "effect", "arguments" => "{\"arguments\":{}}"}
                }
              ]
            }
          else
            %{"role" => "assistant", "content" => "done"}
          end

        {req,
         Req.Response.new(
           status: 200,
           headers: [{"content-type", "application/json"}],
           body:
             Jason.encode!(%{
               "id" => "deadline",
               "choices" => [
                 %{
                   "index" => 0,
                   "message" => message,
                   "finish_reason" => if(index == 0, do: "tool_calls", else: "stop")
                 }
               ]
             })
         )}
      end

      spec = %{
        provider: :openai,
        id: "deadline",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
      }

      model =
        Adapter.new(
          model: spec,
          tool_profile: :chat_tools_v1,
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          total_timeout: 1000,
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        )

      tool =
        ExAgent.Tool.new(
          name: "effect",
          parameters_json_schema: %{"type" => "object"},
          takes_ctx: false,
          call: fn _ ->
            send(owner, :deadline_effect)
            "ok"
          end
        )

      task = Task.async(fn -> ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go") end)
      assert_receive {:deadline_worker, worker, guardian}, 900
      worker_monitor = Process.monitor(worker)
      guardian_monitor = Process.monitor(guardian)
      true = :erlang.suspend_process(guardian)

      on_exit(fn ->
        try do
          :erlang.resume_process(guardian)
        catch
          :error, :badarg -> :ok
        end
      end)

      if timely? do
        send(worker, :release)
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 500
      end

      timer = make_ref()
      Process.send_after(self(), {timer, :past_deadline}, 1100)
      assert_receive {^timer, :past_deadline}, 1500

      unless timely? do
        send(worker, :release)
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 500
      end

      true = :erlang.resume_process(guardian)

      if timely? do
        assert {:ok, _} = Task.await(task)
        assert_receive :deadline_effect
        assert Agent.get(count, & &1) == 2
      else
        assert {:error,
                %ExAgent.RunError{
                  reason: {:model_request_failed, %RequestError{reason: {:timeout, :total}}}
                }} = Task.await(task)

        assert Agent.get(count, & &1) == 1
      end

      refute_receive :deadline_effect, 0
      assert_receive {:DOWN, ^guardian_monitor, :process, ^guardian, :normal}, 1000
    end
  end

  @tag :req_llm_characterization
  test "stock total and receive budgets on finite trickle HTTP are observed separately" do
    {url, count, _} =
      peer(fn socket, _ ->
        data = body()
        :gen_tcp.send(socket, headers(200, byte_size(data), ""))

        for chunk <- Enum.chunk_every(:binary.bin_to_list(data), 32) do
          :gen_tcp.send(socket, :erlang.list_to_binary(chunk))
          Process.sleep(20)
        end
      end)

    started = System.monotonic_time(:millisecond)

    result =
      ReqLLM.generate_text(@model, "synthetic",
        api_key: "synthetic",
        base_url: url,
        max_retries: 0,
        total_timeout: 50,
        receive_timeout: 500
      )

    IO.inspect(
      %{
        total_timeout: 50,
        receive_timeout: 500,
        elapsed_ms: System.monotonic_time(:millisecond) - started,
        result: elem(result, 0)
      },
      label: "R16_TRICKLE"
    )

    assert Agent.get(count, & &1) == 1
  end

  test "public underlying pool timeout rejects queue wait before opening a second connection" do
    start_supervised!(
      {Finch, name: __MODULE__.Pool, pools: %{default: [protocols: [:http1], size: 1, count: 1]}}
    )

    parent = self()

    {url, count, _} =
      peer(fn socket, _ ->
        send(parent, {:holding_pool, self()})

        receive do
          :release -> reply(socket, 200, body())
        after
          2500 -> :ok
        end
      end)

    opts = [
      api_key: "synthetic",
      base_url: url,
      max_retries: 0,
      receive_timeout: 1500,
      req_http_options: [finch: [name: __MODULE__.Pool, pool_timeout: 30]]
    ]

    first = Task.async(fn -> ReqLLM.generate_text(@model, "first", opts) end)
    assert_receive {:holding_pool, server}, 1000

    assert_raise RuntimeError, ~r/excess queuing/, fn ->
      ReqLLM.generate_text(@model, "second", opts)
    end

    assert Agent.get(count, & &1) == 1
    send(server, :release)
    assert {:ok, _} = Task.await(first, 1500)
  end

  defp peer(handler) do
    count = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listen)
    server = spawn(fn -> accept(listen, port, count, handler) end)

    on_exit(fn ->
      Process.exit(server, :kill)
      :gen_tcp.close(listen)
    end)

    {"http://127.0.0.1:#{port}/v1", count, server}
  end

  defp accept(listener, port, count, handler) do
    case :gen_tcp.accept(listener, 2500) do
      {:ok, socket} ->
        read_headers(socket, "")
        Agent.update(count, &(&1 + 1))
        handler.(socket, port)
        :gen_tcp.close(socket)
        accept(listener, port, count, handler)

      {:error, _} ->
        :ok
    end
  end

  defp read_headers(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [header, data] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, header)
        remaining = String.to_integer(length) - byte_size(data)
        if remaining > 0, do: {:ok, _} = :gen_tcp.recv(socket, remaining, 1000)

      _ ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 1000)
        read_headers(socket, buffer <> bytes)
    end
  end

  defp headers(status, size, extra),
    do:
      "HTTP/1.1 #{status} Synthetic\r\nContent-Type: application/json\r\nContent-Length: #{size}\r\nConnection: close\r\n#{extra}\r\n"

  defp reply(socket, status, data, extra \\ ""),
    do: :gen_tcp.send(socket, headers(status, byte_size(data), extra) <> data)
end

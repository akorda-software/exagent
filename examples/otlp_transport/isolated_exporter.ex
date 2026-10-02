defmodule OTLPTransportProbe.IsolatedExporter do
  @moduledoc """
  Packaged experimental application-owned native OTel callback with one disposable VM
  per batch. The launcher owns and registers that VM's OS group, never kills a
  PID obtained outside its own spawn, and bounds trusted IPC and lifetime.
  ExAgent core does not install this recipe or start another VM by default.
  """
  @behaviour :otel_exporter_traces

  def init(opts) do
    trusted = Application.fetch_env!(:otlp_isolated_probe, :transport)

    state =
      Map.merge(trusted, %{
        deadline_ms: Map.get(opts, :deadline_ms, 2_000),
        rpc_deadline_ms: Map.get(opts, :rpc_deadline_ms, 250),
        fault: Map.get(opts, :fault, "none")
      })

    if state.deadline_ms in 100..5_000 and state.rpc_deadline_ms in 1..5_000 and
         state.fault in ["none", "shutdown_block", "before_rpc_hold"] do
      {:ok, state}
    else
      {:error, :invalid_finite_profile}
    end
  end

  def shutdown(_), do: :ok

  def export(table, resource, state) do
    case :otel_otlp_traces.to_proto(table, resource) do
      :empty ->
        :ok

      request ->
        # Optional application-owned projection of the public converter map.
        # The core/stock SDK and the default recipe remain backend-neutral.
        request =
          case Map.get(state, :request_profile) do
            nil -> request
            module -> module.project(request)
          end

        count = Enum.sum(for r <- request.resource_spans, s <- r.scope_spans, do: length(s.spans))
        payload = :erlang.term_to_binary(request)

        if count in 1..8 and byte_size(payload) <= 65_536 and
             :atomics.compare_exchange(state.gate, 1, 0, 1) == :ok do
          owner = self()
          token = make_ref()
          spawn(fn -> lease(owner, token, payload, count, state) end)

          receive do
            {^token, result} -> result
          after
            state.deadline_ms + 1_500 -> :failed_not_retryable
          end
        else
          send(
            state.observer,
            {:isolated_receipt,
             %{
               "source" => "admission",
               "sent" => 0,
               "reported_accepted" => 0,
               "rejected" => 0,
               "unknown" => 0,
               "dropped" => count,
               "oversized_or_busy" => true
             }}
          )

          :failed_not_retryable
        end
    end
  end

  defp lease(owner, token, payload, count, state) do
    lease = self()
    {guard, ref} = spawn_monitor(fn -> own_port(owner, token, payload, count, state, lease) end)
    send(state.observer, {:isolated_lease, lease})

    lease_watch(%{
      guard: guard,
      ref: ref,
      gate: state.gate,
      observer: state.observer,
      opening: false,
      identities: [],
      released: false,
      until: System.monotonic_time(:millisecond) + state.deadline_ms + 2_000
    })
  end

  defp lease_watch(s) do
    receive do
      :opening ->
        lease_watch(%{s | opening: true})

      {:own_os_pid, pid} when is_integer(pid) and pid > 0 ->
        lease_watch(%{s | identities: [{pid, os_identity(pid)} | s.identities]})

      {:closed_confirmation, guard} when guard == s.guard ->
        :atomics.put(s.gate, 1, 0)
        send(guard, {:gate_released, self()})
        lease_watch(%{s | released: true})

      {:DOWN, ref, :process, guard, _} when ref == s.ref and guard == s.guard ->
        if not s.released, do: release_after_death(s)
    after
      max(s.until - System.monotonic_time(:millisecond), 0) ->
        Process.demonitor(s.ref, [:flush])
        send(s.observer, {:isolated_admission_closed, :unverified_cleanup})
    end
  end

  defp release_after_death(s) do
    verified =
      not s.opening or
        (length(s.identities) == 2 and
           Enum.all?(s.identities, fn {pid, identity} ->
             identity == nil or os_identity(pid) != identity
           end))

    cond do
      verified ->
        :atomics.put(s.gate, 1, 0)

      System.monotonic_time(:millisecond) < s.until ->
        Process.sleep(5)
        release_after_death(s)

      true ->
        send(s.observer, {:isolated_admission_closed, :unverified_cleanup})
    end
  end

  # These read-only identities come solely from our own spawn/launcher. No
  # signal or kill ever uses /proc inspection or an externally discovered PID.
  defp os_identity(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} ->
        stat |> String.split(") ", parts: 2) |> List.last() |> String.split() |> Enum.at(19)

      _ ->
        nil
    end
  end

  defp own_port(owner, token, payload, count, state, lease) do
    owner_ref = Process.monitor(owner)

    args = [
      state.launcher,
      "--elixir",
      state.elixir,
      "--beam-path",
      state.beam_path,
      "--worker",
      state.worker,
      "--port",
      Integer.to_string(state.port),
      "--count",
      Integer.to_string(count),
      "--deadline-ms",
      Integer.to_string(state.deadline_ms),
      "--rpc-deadline-ms",
      Integer.to_string(state.rpc_deadline_ms),
      "--fault",
      state.fault
    ]

    send(lease, :opening)

    port =
      Port.open({:spawn_executable, state.python}, [
        :binary,
        {:packet, 4},
        :exit_status,
        :use_stdio,
        {:args, args}
      ])

    port_ref = :erlang.monitor(:port, port)
    {:os_pid, launcher_pid} = Port.info(port, :os_pid)
    send(lease, {:own_os_pid, launcher_pid})
    send(state.observer, {:isolated_port, owner, self(), port, Port.info(port, :os_pid)})
    accepted = Port.command(port, payload, [:nosuspend])
    until = System.monotonic_time(:millisecond) + state.deadline_ms + 1_000

    watch(%{
      owner: owner,
      owner_ref: owner_ref,
      owner_alive: true,
      token: token,
      port: port,
      port_ref: port_ref,
      state: state,
      count: count,
      receipt: nil,
      accepted: accepted,
      until: until,
      request_bytes: byte_size(payload),
      cancelling: false,
      lease: lease
    })
  rescue
    _ ->
      send(owner, {token, :failed_not_retryable})

      send(
        state.observer,
        {:isolated_receipt,
         %{
           "source" => "launcher_failure",
           "sent" => 0,
           "reported_accepted" => 0,
           "rejected" => 0,
           "unknown" => count,
           "group_closed" => false
         }}
      )
  end

  defp watch(s) do
    timeout = max(s.until - System.monotonic_time(:millisecond), 0)

    receive do
      {port, {:data, bytes}} when port == s.port and byte_size(bytes) <= 4_096 ->
        case Jason.decode(bytes) do
          {:ok, %{"type" => "started", "vm_pid" => pid, "registered" => true}}
          when is_integer(pid) and pid > 0 ->
            send(s.state.observer, {:isolated_group, pid})
            send(s.lease, {:own_os_pid, pid})
            watch(s)

          {:ok, %{"type" => "closed"} = receipt} ->
            watch(%{s | receipt: receipt})

          _ ->
            cancel(s)
        end

      {port, {:exit_status, status}} when port == s.port ->
        finish(s, status)

      {:DOWN, ref, :process, owner, _} when ref == s.owner_ref and owner == s.owner ->
        cancel(%{s | owner_alive: false})

      {:DOWN, ref, :port, port, _} when ref == s.port_ref and port == s.port ->
        finish(s, 1)
    after
      timeout -> cancel(s)
    end
  end

  defp cancel(s) do
    if not s.cancelling and Port.info(s.port) != nil do
      Port.command(s.port, "CANCEL", [:nosuspend])
      watch(%{s | cancelling: true, until: System.monotonic_time(:millisecond) + 500})
    else
      finish(s, 1)
    end
  end

  defp finish(s, status) do
    if Port.info(s.port) != nil, do: Port.close(s.port)
    :erlang.demonitor(s.port_ref, [:flush])
    Process.demonitor(s.owner_ref, [:flush])

    receipt =
      s.receipt ||
        %{
          "sent" => if(s.accepted, do: s.count, else: 0),
          "unknown" => s.count,
          "group_closed" => false,
          "result" => "failed"
        }

    if receipt["group_closed"] == true and status == 0 do
      send(s.lease, {:closed_confirmation, self()})

      receive do
        {:gate_released, lease} when lease == s.lease -> :ok
      after
        500 -> :ok
      end
    end

    alive = s.owner_alive and Process.alive?(s.owner)

    receipt =
      Map.merge(receipt, %{
        "request_etf_bytes" => s.request_bytes,
        "caller_alive" => alive,
        "launcher_exit" => status
      })

    send(s.state.observer, {:isolated_receipt, receipt})

    success =
      status == 0 and alive and not s.cancelling and receipt["group_closed"] == true and
        receipt["result"] == "ok" and receipt["reported_accepted"] == s.count and
        receipt["rejected"] == 0 and
        receipt["unknown"] == 0

    send(s.owner, {s.token, if(success, do: :ok, else: :failed_not_retryable)})
  end
end

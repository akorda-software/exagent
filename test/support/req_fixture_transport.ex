defmodule ExAgent.Test.ReqTransport do
  @moduledoc false

  @registry __MODULE__.Registry

  # A test owner binds its current fixture callback. Registry monitors the owner;
  # Task ancestry or the buffered worker's reciprocal owner/guardian monitors
  # carry this binding. Execution stays in the requesting process, preserving
  # blocked-callback cancellation. Distinct module slots keep parent and child
  # fixtures separate; unrelated supervised callers require an explicit allow.
  def bind(callback, adapter \\ __MODULE__) when is_function(callback, 1) do
    key = {self(), adapter}

    case Registry.register(@registry, key, callback) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        Registry.update_value(@registry, key, fn _ -> callback end)
    end

    adapter
  end

  def allow(pid, adapter \\ __MODULE__) do
    callback = capture(adapter)
    {:ok, _} = Registry.register(@registry, {pid, adapter}, callback)
    :ok
  end

  def capture(adapter \\ __MODULE__) do
    [{owner, callback}] = Registry.lookup(@registry, {self(), adapter})
    true = owner == self()
    callback
  end

  def run(request, adapter \\ __MODULE__) do
    owners =
      [self()] ++ List.wrap(Process.get(:"$callers")) ++ List.wrap(Process.get(:"$ancestors"))

    callback = find_callback(owners, adapter) || buffered_callback(adapter)

    if callback do
      callback.(request)
    else
      raise "no Req fixture callback bound to this test owner"
    end
  end

  defp find_callback(owners, adapter) do
    Enum.find_value(owners, fn owner ->
      case Registry.lookup(@registry, {owner, adapter}) do
        [{_binding_owner, callback}] -> callback
        [] -> nil
      end
    end)
  end

  defp buffered_callback(adapter) do
    {:links, links} = Process.info(self(), :links)

    Enum.find_value(links, fn guardian ->
      with true <- is_pid(guardian),
           {:monitors, monitors} <- Process.info(guardian, :monitors),
           {:monitored_by, owners} <- Process.info(guardian, :monitored_by) do
        Enum.find_value(owners, fn owner ->
          if {:process, owner} in monitors do
            case Process.info(owner, :dictionary) do
              {:dictionary, dictionary} ->
                find_callback(
                  [owner] ++
                    List.wrap(dictionary[:"$callers"]) ++ List.wrap(dictionary[:"$ancestors"]),
                  adapter
                )

              nil ->
                nil
            end
          end
        end)
      else
        _ -> nil
      end
    end)
  end
end

defmodule ExAgent.Test.ReqTransport.Child do
  @moduledoc false
  def run(request), do: ExAgent.Test.ReqTransport.run(request, __MODULE__)
end

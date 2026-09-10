defmodule ExAgent.Providers.EventStream do
  @moduledoc false
  defstruct [:source, :initial, :step]

  # Own the latest upstream continuation, including while callbacks raise. A
  # resource next/after pair would retain the previous continuation when next
  # raises, potentially leaking the newly suspended HTTP resource (or closing
  # an old continuation twice). Terminal steps close without another read.
  def transform(source, initial, step),
    do: %__MODULE__{source: source, initial: initial, step: step}

  def reduce(stream, command, reducer) do
    continuation = fn command ->
      Enumerable.reduce(stream.source, command, fn item, _ -> {:suspend, item} end)
    end

    state = %{
      continuation: continuation,
      acc: stream.initial,
      step: stream.step,
      pending: [],
      done: false
    }

    drive(state, command, reducer)
  end

  defp drive(state, {:halt, acc}, _reducer) do
    close(state)
    {:halted, acc}
  end

  defp drive(state, {:suspend, acc}, reducer),
    do: {:suspended, acc, fn command -> drive(state, command, reducer) end}

  defp drive(%{pending: [item | rest]} = state, {:cont, acc}, reducer) do
    command = safely(state, fn -> reducer.(item, acc) end)
    drive(%{state | pending: rest}, command, reducer)
  end

  defp drive(%{done: true}, {:cont, acc}, _reducer), do: {:done, acc}

  defp drive(state, {:cont, acc}, reducer) do
    {item, state} =
      case state.continuation.({:cont, nil}) do
        {:suspended, item, continuation} -> {item, %{state | continuation: continuation}}
        {status, _} when status in [:done, :halted] -> {:eof, %{state | continuation: nil}}
      end

    state =
      case safely(state, fn -> state.step.(item, state.acc) end) do
        {:halt, events, next_acc} ->
          close(state)
          %{state | continuation: nil, acc: next_acc, pending: events, done: true}

        {:cont, events, next_acc} when item != :eof ->
          %{state | acc: next_acc, pending: events}
      end

    drive(state, {:cont, acc}, reducer)
  end

  defp safely(state, fun) do
    try do
      fun.()
    catch
      kind, reason ->
        close(state)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp close(%{continuation: nil}), do: :ok
  defp close(%{continuation: continuation}), do: continuation.({:halt, nil})
end

defimpl Enumerable, for: ExAgent.Providers.EventStream do
  def reduce(stream, command, reducer),
    do: ExAgent.Providers.EventStream.reduce(stream, command, reducer)

  def count(_), do: {:error, __MODULE__}
  def member?(_, _), do: {:error, __MODULE__}
  def slice(_), do: {:error, __MODULE__}
end

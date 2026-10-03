defmodule ExAgent.ReqFixtureTransportTest do
  use ExUnit.Case, async: true

  alias ExAgent.Test.ReqTransport

  test "parallel owners and nested tasks execute their own module adapter" do
    owner = self()

    tasks =
      for value <- ["first", "second"] do
        Task.async(fn ->
          adapter =
            ReqTransport.bind(fn request ->
              send(owner, {:callback, value, self()})
              {request, Req.Response.new(status: 200, body: value)}
            end)

          child =
            ReqTransport.bind(
              fn request ->
                {request, Req.Response.new(status: 200, body: value <> " child")}
              end,
              ReqTransport.Child
            )

          send(owner, {:ready, self()})

          receive do
            :go -> :ok
          end

          nested =
            Task.async(fn ->
              ExAgent.Models.ReqLLMBuffered.run(
                fn ->
                  Req.get!(url: "https://fixture.invalid", adapter: adapter)
                end,
                5000
              )
            end)

          parent_response = Task.await(nested).body

          child_response =
            ExAgent.Models.ReqLLMBuffered.run(
              fn ->
                Req.get!(url: "https://fixture.invalid", adapter: child)
              end,
              5000
            )

          assert child_response.body == value <> " child"
          {self(), parent_response}
        end)
      end

    assert_receive {:ready, first}
    assert_receive {:ready, second}

    unbound =
      Task.async(fn ->
        assert_raise RuntimeError, "no Req fixture callback bound to this test owner", fn ->
          Req.get!(url: "https://fixture.invalid", adapter: ReqTransport)
        end
      end)

    Task.await(unbound)
    send(first, :go)
    send(second, :go)
    assert Enum.map(tasks, &Task.await/1) |> Enum.map(&elem(&1, 1)) == ["first", "second"]
    assert_receive {:callback, "first", first_worker}
    assert_receive {:callback, "second", second_worker}
    assert first_worker != second_worker

    assert released?(first, 100)
    assert released?(second, 100)
  end

  defp released?(owner, attempts) do
    cond do
      Enum.all?(
        [ReqTransport, ReqTransport.Child],
        &(Registry.lookup(ReqTransport.Registry, {owner, &1}) == [])
      ) ->
        true

      attempts == 0 ->
        false

      true ->
        receive do
        after
          10 -> released?(owner, attempts - 1)
        end
    end
  end
end

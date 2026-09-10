defmodule ExAgent.EventErrorProjectionTest do
  use ExUnit.Case, async: true

  alias ExAgent.{CheckpointError, Event, RequestError, RunError}

  @sentinel "SENTINEL_EVENT_PRIVATE_RUNTIME"

  test "RequestError keeps provider, HTTP status and safe cause categories distinguishable" do
    for {provider, status, reason} <- [
          {:openai, 401, :http_error},
          {:openai, 429, :http_error},
          {:anthropic, nil, :timeout}
        ] do
      error = request_error(provider, status, reason)
      payload = Event.error_payload(error)

      assert %{
               type: :runtime,
               reason: %{
                 exception: "Elixir.ExAgent.RequestError",
                 provider: projected_provider,
                 status: ^status,
                 reason: projected_reason
               }
             } = payload

      assert projected_provider === Atom.to_string(provider)
      assert projected_reason === Atom.to_string(reason)
      assert_private_runtime_absent(payload)
    end
  end

  test "RunError and CheckpointError retain the safe nested request diagnosis" do
    for {provider, status, reason} <- [
          {:openai, 401, :http_error},
          {:openai, 429, :http_error},
          {:anthropic, nil, :timeout}
        ] do
      request = request_error(provider, status, reason)

      run = %RunError{
        reason: {:model_request_failed, request},
        partial: %{model: request.model, output: nil, messages: [], new_messages: []}
      }

      checkpoint = %CheckpointError{
        operation: :chat,
        reason: :unavailable,
        revision: 7,
        result: {:error, run}
      }

      run_payload = Event.error_payload(run)
      checkpoint_payload = Event.error_payload(checkpoint)

      assert %{type: :run, reason: ["model_request_failed", diagnosis]} = run_payload
      assert diagnosis.provider === Atom.to_string(provider)
      assert diagnosis.status === status
      assert diagnosis.reason === Atom.to_string(reason)
      assert checkpoint_payload.result.error === run_payload
      assert checkpoint_payload.result.status === :error
      assert_private_runtime_absent(run_payload)
      assert_private_runtime_absent(checkpoint_payload)
    end
  end

  test "owned tuple categories survive without arbitrary reason data" do
    payload =
      :openai
      |> request_error(nil, {:stream_limit, :max_response_bytes})
      |> Event.error_payload()

    assert payload.reason.reason === ["stream_limit", "max_response_bytes"]
    assert_private_runtime_absent(payload)

    for reason <- [
          @sentinel,
          %{body: @sentinel, headers: %{"authorization" => @sentinel}},
          %RuntimeError{message: @sentinel},
          {:transport_error, %RuntimeError{message: @sentinel}},
          {:unknown_category, @sentinel}
        ] do
      payload = :openai |> request_error(nil, reason) |> Event.error_payload()
      assert_private_runtime_absent(payload)
    end
  end

  test "malformed provider and HTTP status values are omitted safely" do
    for {provider, status} <- [
          {%{api_key: @sentinel}, @sentinel},
          {"Bearer " <> @sentinel, 99},
          {:openai, 600}
        ] do
      payload = provider |> request_error(status, :http_error) |> Event.error_payload()
      assert payload.reason.status === nil
      assert_private_runtime_absent(payload)
    end
  end

  test "custom provider identifiers remain usable without exposing runtime configuration" do
    payload = "custom.provider" |> request_error(503, :http_error) |> Event.error_payload()
    assert payload.reason.provider === "custom.provider"
    assert payload.reason.status === 503
    assert payload.reason.reason === "http_error"
    assert_private_runtime_absent(payload)
  end

  defp request_error(provider, status, reason) do
    %RequestError{
      provider: provider,
      status: status,
      reason: reason,
      model: %ExAgent.Models.Test{label: @sentinel},
      body: %{body: @sentinel, headers: %{"authorization" => @sentinel}, api_key: @sentinel},
      partial_response: %ExAgent.Message.Response{
        parts: [%ExAgent.Message.Part.Text{content: @sentinel}]
      }
    }
  end

  defp assert_private_runtime_absent(payload) do
    encoded = Jason.encode!(payload)
    refute encoded =~ @sentinel
    refute encoded =~ "authorization"
    refute encoded =~ "api_key"
  end
end

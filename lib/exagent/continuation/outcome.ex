defmodule ExAgent.Continuation.Outcome do
  @moduledoc false
  alias ExAgent.Continuation.Record
  alias ExAgent.Message

  def hash(bytes) when is_binary(bytes) do
    with {:ok, data} <- Jason.decode(bytes), do: Record.digest(data)
  end

  def hash(%Message.Part.ToolReturn{} = part), do: part |> encode() |> hash()

  def encode(part), do: Message.to_json([%Message.Request{parts: [part]}])

  def call_hash(call) do
    bytes = Message.to_json([%Message.Response{parts: [call]}])
    hash(bytes)
  end

  def model(response, model_data, available? \\ true) do
    {:ok, response_hash} = response |> then(&Message.to_json([&1])) |> hash()
    {:ok, state_hash} = Record.digest(model_data)

    %{
      "status" => "succeeded",
      "data" => %{
        "runtime_model_version" => 1,
        "response_hash" => response_hash,
        "model_state_hash" => if(available?, do: state_hash),
        "state_available" => available?
      }
    }
  end

  def model_valid?(data),
    do:
      Record.exact?(
        data,
        ~w(runtime_model_version response_hash model_state_hash state_available)
      ) and
        data["runtime_model_version"] == 1 and hash?(data["response_hash"]) and
        is_boolean(data["state_available"]) and
        if(data["state_available"],
          do: hash?(data["model_state_hash"]),
          else: is_nil(data["model_state_hash"])
        )

  def model_tagged?(data), do: is_map(data) and Map.has_key?(data, "runtime_model_version")

  def new(part, phase \\ "raw", raw_hash \\ nil) do
    with {:ok, hash} <- hash(part) do
      {:ok,
       %{
         "status" => Atom.to_string(part.status),
         "data" => %{
           "runtime_outcome_version" => 1,
           "phase" => phase,
           "raw_hash" => raw_hash || hash,
           "result_hash" => hash
         }
       }}
    end
  end

  def valid?(%{"runtime_outcome_version" => 1} = data) do
    Record.exact?(data, ~w(runtime_outcome_version phase raw_hash result_hash)) and
      data["phase"] in ~w(raw final) and hash?(data["raw_hash"]) and hash?(data["result_hash"]) and
      (data["phase"] == "final" or data["raw_hash"] === data["result_hash"])
  end

  def valid?(_), do: false
  def hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  def tagged?(data), do: is_map(data) and Map.has_key?(data, "runtime_outcome_version")
end

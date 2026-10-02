defmodule ExAgent.Continuation.RequestData do
  @moduledoc false
  alias ExAgent.{Message, Tool}
  alias ExAgent.Continuation.{Frame, Record}

  @fields ~w(request_version messages instructions settings tools output_fingerprint model_state_hash model_ref)

  # The structural frame, not a public mode option, selects the new evidence.
  def capture(run, frame, config, %{"frame_version" => version} = root)
      when version in [10, 11] do
    with :ok <- Frame.validate(root),
         true <- root["children"][frame["run_id"]]["frame"] === frame,
         {:ok, data} <- capture(run, frame, config),
         {:ok, descriptors} <- descriptors(Map.values(run.prepared_tools)) do
      data = Map.merge(data, %{"request_version" => 2, "tool_descriptors" => descriptors})
      if valid10?(data), do: {:ok, data}, else: {:error, :unrepresentable_model_request}
    else
      _ -> {:error, :unrepresentable_model_request}
    end
  end

  def capture(run, frame, config, _), do: capture(run, frame, config)

  defp descriptors(tools) do
    Enum.reduce_while(tools, {:ok, %{}}, fn tool, {:ok, acc} ->
      case Frame.fingerprint_data(tool) do
        {:ok, data} -> {:cont, {:ok, Map.put(acc, tool.name, data)}}
        error -> {:halt, error}
      end
    end)
  end

  def valid10?(data) do
    Record.exact?(data, @fields ++ ["tool_descriptors"]) and
      data["request_version"] === 2 and Record.reference?(data["model_ref"]) and
      hash?(data["model_state_hash"]) and
      (is_nil(data["output_fingerprint"]) or hash?(data["output_fingerprint"])) and
      is_map(data["settings"]) and is_map(data["tools"]) and
      is_map(data["tool_descriptors"]) and
      Enum.sort(Map.keys(data["tools"])) === Enum.sort(Map.keys(data["tool_descriptors"])) and
      Enum.all?(data["tool_descriptors"], fn {name, descriptor} ->
        descriptor?(name, descriptor) and Record.digest(descriptor) == {:ok, data["tools"][name]}
      end) and
      match?({:ok, _}, Message.from_json(data["messages"])) and
      match?({:ok, [%Message.Request{}]}, Message.from_json(data["instructions"])) and
      Tool.JSON.normalize(data) === {:ok, data} and
      byte_size(Jason.encode!(data)) <= Record.max_bytes()
  rescue
    _ -> false
  end

  defp descriptor?(name, d) do
    Record.text?(name) and
      Record.exact?(
        d,
        ~w(definition kind takes_ctx max_retries) ++
          if(Map.has_key?(d, "delegation"), do: ["delegation"], else: []) ++
          if(Map.has_key?(d, "execution_binding"), do: ["execution_binding"], else: [])
      ) and
      d["kind"] in ~w(function output external unapproved) and is_boolean(d["takes_ctx"]) and
      Record.counter?(d["max_retries"]) and
      Record.exact?(d["definition"], ~w(name description parameters)) and
      d["definition"]["name"] === name and
      (is_nil(d["definition"]["description"]) or is_binary(d["definition"]["description"])) and
      (is_map(d["definition"]["parameters"]) or is_boolean(d["definition"]["parameters"])) and
      (not Map.has_key?(d, "delegation") or delegation?(d["delegation"])) and
      (not Map.has_key?(d, "execution_binding") or
         ExAgent.MCP.Binding.valid?(d["execution_binding"]))
  end

  defp delegation?(d) do
    Record.exact?(d, ~w(descriptor_version prompt_arg definition policy model_ref)) and
      d["descriptor_version"] === 1 and Record.text?(d["prompt_arg"]) and
      Enum.all?(~w(definition policy model_ref), &Record.reference?(d[&1]))
  end

  defp hash?(value),
    do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  def restore(state, %{"request_version" => 2} = data, %{"frame_version" => version} = root)
      when version in [10, 11] do
    with :ok <- Frame.validate(root),
         true <-
           root["children"][state.continuation_frame["run_id"]]["frame"] ===
             state.continuation_frame,
         true <- valid10?(data),
         {:ok, current} <- descriptors(Map.values(state.prepared_tools)),
         true <- current === data["tool_descriptors"] do
      restore(state, data |> Map.delete("tool_descriptors") |> Map.put("request_version", 1))
    else
      _ -> {:error, :retry_model_request_changed}
    end
  end

  def restore(state, data, _), do: restore(state, data)

  def capture(run, frame, config) do
    with {:ok, inventory} <- Frame.inventory(Map.values(run.prepared_tools)),
         {:ok, fingerprint} <- Frame.output_fingerprint(run.params),
         {:ok, state_hash} <- Record.digest(frame["model_data"]),
         {:ok, settings} <-
           Tool.JSON.normalize(Map.from_struct(run.settings) |> Map.delete(:timeout)) do
      {:ok,
       %{
         "request_version" => 1,
         "messages" => Message.to_json(run.request_messages || run.messages),
         "instructions" => Message.to_json([%Message.Request{parts: run.params.instructions}]),
         "settings" => settings,
         "tools" => inventory,
         "output_fingerprint" => fingerprint,
         "model_state_hash" => state_hash,
         "model_ref" => config.model_ref
       }}
    end
  rescue
    _ -> {:error, :unrepresentable_model_request}
  end

  def restore(state, data) do
    with true <-
           Record.exact?(
             data,
             ~w(request_version messages instructions settings tools output_fingerprint model_state_hash model_ref)
           ) and data["request_version"] == 1,
         {:ok, messages} <- Message.from_json(data["messages"]),
         true <- ExAgent.Retention.executable?(messages),
         {:ok, [%Message.Request{parts: instructions}]} <- Message.from_json(data["instructions"]),
         {:ok, tools} <- Frame.inventory(Map.values(state.prepared_tools)),
         true <- tools === data["tools"],
         true <- Frame.output_fingerprint(state.params) == {:ok, data["output_fingerprint"]},
         true <-
           Record.digest(state.continuation_frame["model_data"]) ==
             {:ok, data["model_state_hash"]},
         {:ok, settings} <-
           Tool.JSON.normalize(Map.from_struct(state.settings) |> Map.delete(:timeout)),
         true <- settings === data["settings"] do
      {:ok,
       %{state | request_messages: messages, params: %{state.params | instructions: instructions}}}
    else
      _ -> {:error, :retry_model_request_changed}
    end
  end
end

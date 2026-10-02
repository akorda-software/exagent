# Live example for an explicitly declared non-reasoning OpenAI Chat profile.
#
#   mix run examples/streaming.exs
#
# Prints text deltas as they arrive (typewriter effect) then the final result.

key = System.get_env("OPENAI_API_KEY")

unless key do
  IO.puts("OPENAI_API_KEY not set — skipping.")
  System.halt(0)
end

alias ExAgent

model =
  ExAgent.Models.ReqLLM.new(
    model: %{
      provider: :openai,
      id: "gpt-4o-mini",
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
      extra: %{wire: %{protocol: "openai_chat"}}
    },
    api_key: key,
    tool_profile: :chat_tools_v1
  )

agent =
  ExAgent.new(
    model: model,
    instructions: "Count from 1 to 5 slowly, one number per line.",
    model_settings: [max_tokens: 256, temperature: 0.0]
  )

IO.puts("=== STREAMING ===")

ExAgent.run_stream(agent, "count!")
|> Stream.each(fn
  {:delta, text} ->
    IO.write(text)

  {:result, %{usage: usage}} ->
    IO.puts("\n\n=== FINAL ===\ntokens in=#{usage.input_tokens} out=#{usage.output_tokens}")

  {:error, reason} ->
    IO.puts("\nERROR: #{Exception.message(reason)}")
end)
|> Stream.run()

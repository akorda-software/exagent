# Migration example, deliberately no live request:
#   mix run examples/zai_anthropic.exs
#
# `zai:...` now means the stock ZAI provider, not the former Anthropic alias.
# Keep Anthropic endpoint/model/auth explicit to preserve that old destination.
# Stock bearer authentication is tested offline; this GLM reasoning/tools route
# is not qualified and must not be relabelled non-reasoning to bypass the guard.

model =
  ExAgent.Models.ReqLLM.new(
    model: %{
      provider: :anthropic,
      id: "glm-4.5-air",
      capabilities: %{reasoning: %{enabled: true}}
    },
    auth_token: "synthetic-migration-example",
    base_url: "https://api.z.ai/api/anthropic"
  )

{:error, %ExAgent.RequestError{reason: {:unsupported, :anthropic_reasoning_continuation}}} =
  ExAgent.Model.request(
    model,
    [ExAgent.Message.new_request([%ExAgent.Message.Part.User{content: "hello"}])],
    nil,
    %ExAgent.ModelRequestParameters{}
  )

IO.puts(
  "ZAI Anthropic reasoning/continuation remains closed before IO; see docs/guides/migration.md."
)

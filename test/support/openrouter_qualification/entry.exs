# Explicit opt-in precedes credential reads, artifacts and Model/network IO.
{opts, rest, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      live: :boolean,
      offline_check: :boolean,
      model: :string,
      artifacts: :string,
      max_admissions: :integer,
      budget_usd: :float,
      reserve_usd: :float,
      cases: :string,
      catalog: :string,
      source_id: :string
    ]
  )

unless opts[:live] == true or opts[:offline_check] == true do
  IO.puts(:stderr, "No Model IO: pass --live explicitly, or --offline-check for synthetic TCP.")
  System.halt(64)
end

true = rest == [] and invalid == [] and not (opts[:live] == true and opts[:offline_check] == true)
model_id = Keyword.fetch!(opts, :model)

true =
  model_id in [
    "openai/gpt-4o-mini",
    "openai/gpt-6-luna",
    "z-ai/glm-5.3-flash",
    "deepseek/deepseek-v4.1-flash"
  ]

text_only = model_id in ["z-ai/glm-5.3-flash", "deepseek/deepseek-v4.1-flash"]
none = model_id == "openai/gpt-6-luna"
live = opts[:live] == true
artifact = opts |> Keyword.fetch!(:artifacts) |> Path.expand()
true = File.dir?(Path.dirname(artifact))
false = File.exists?(artifact)
max_count = opts[:max_admissions] || 30
max_usd = opts[:budget_usd] || 2.0
minimum_unit = if(none, do: 0.05, else: if(text_only, do: 0.6, else: 0.025))
unit = opts[:reserve_usd] || minimum_unit

true =
  max_count in 1..80 and max_usd > 0 and max_usd <= 5 and unit >= minimum_unit and unit <= max_usd

true = to_string(Application.spec(:req_llm, :vsn)) == "1.27.0"
key = if live, do: System.fetch_env!("OPENROUTER_API_KEY"), else: "synthetic-not-a-credential"
true = byte_size(key) > 0
:ok = File.mkdir(artifact)

for name <- [
      "G2_NONE_MODEL",
      "G2_GLOBAL_LEDGER",
      "G2_NONE_LIVE_AUTHORIZED",
      "G2_LIVE_AUTHORIZED",
      "G2_TEXT_LIVE_AUTHORIZED"
    ] do
  System.delete_env(name)
end

System.put_env("G2_ROOT", artifact)
System.put_env("G2_ARTIFACT_ROOT", artifact)
System.put_env("G2_HARNESS_SOURCE", __DIR__)
System.put_env("G2_LOAD_ONLY", "1")
System.put_env("G2_BOUNDED_INPUT", "1")
System.put_env("G2_REQUESTED_MODEL", model_id)
if none, do: System.put_env("G2_NONE_MODEL", "1")
Code.require_file("g2.exs", __DIR__)
Code.require_file("input_budget.exs", __DIR__)

# Load the selected optional helper before compiling its consumer.
if not live or text_only do
  System.put_env("G2_TCP_LIBRARY", "1")
  System.put_env("G2_SYNTHETIC_NAME", "offline-fixture")
  Code.require_file("synthetic.exs", __DIR__)

  if text_only do
    System.put_env("G2_TEXT_LIBRARY", "1")
    Code.require_file("text_probe.exs", __DIR__)
  end

  System.put_env("G2_ARTIFACT_ROOT", artifact)
end

defmodule PortableQualification do
  def fingerprint do
    paths = ["mix.exs", "mix.lock", "README.md"] ++ Path.wildcard("{lib,config}/**/*.{ex,exs}")

    files =
      Map.new(Enum.sort(paths), fn p ->
        {p, Base.encode16(:crypto.hash(:sha256, File.read!(p)), case: :lower)}
      end)

    digest =
      files
      |> Enum.sort()
      |> Enum.map(&Tuple.to_list/1)
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{sha256: digest, files: files}
  end

  if Code.ensure_loaded?(G2.TextProbe) do
    def text(model_id, key, url) do
      model = G2.TextProbe.model(model_id, :openrouter, key, url)

      agent =
        ExAgent.new(
          model: model,
          capabilities: [G2.Admission, G2.InputBudget],
          output_retries: 0,
          model_settings: [max_tokens: 256],
          usage_limits: %ExAgent.UsageLimits{request_limit: 1, tool_calls_limit: 0}
        )

      result = ExAgent.run(agent, "Reply with exactly G2_OK and nothing else.")
      projection = G2.TextProbe.project(result)

      record = %{
        name: "text_sync",
        model: model_id,
        profile: "buffered_text_only",
        accepted:
          projection.output_exact and projection.message_roundtrip and
            projection.request_count == 1,
        effects: 0,
        admissions: 1,
        result: projection
      }

      File.write!(G2.path("results.jsonl"), Jason.encode!(record) <> "\n", [:append])
      record
    end
  end
end

fingerprint = PortableQualification.fingerprint()

catalog =
  if opts[:catalog] do
    Jason.decode!(File.read!(opts[:catalog]))
  else
    true = live

    response =
      Req.get!("https://openrouter.ai/api/v1/models", retry: false, receive_timeout: 30_000)

    true = response.status == 200
    %{"models" => response.body["data"]}
  end

target = Enum.find(catalog["models"], &(&1["id"] == model_id))
true = is_map(target)

if none do
  true =
    target["reasoning"]["mandatory"] == false and
      "none" in target["reasoning"]["supported_efforts"]
end

if text_only, do: true = target["reasoning"]["default_enabled"] == true
File.write!(G2.path("catalog-targets.json"), Jason.encode!(%{models: [target]}, pretty: true))

selection =
  if opts[:cases],
    do: String.split(opts[:cases], ",", trim: true),
    else: if(text_only, do: ["text_sync"], else: Enum.map(G2.cases(), &elem(&1, 0)))

true = selection != [] and length(selection) == length(Enum.uniq(selection))

true =
  Enum.all?(selection, fn selected ->
    Enum.any?(G2.cases(), fn c -> elem(c, 0) == selected end)
  end)

if text_only, do: true = selection == ["text_sync"]

manifest = %{
  model: model_id,
  profile:
    if(text_only,
      do: "buffered_text_only",
      else: if(none, do: "chat_tools_v1/none", else: "chat_tools_v1")
    ),
  source: fingerprint,
  declared_source_id: opts[:source_id],
  live: live,
  requested_cases: selection,
  max_admissions: max_count,
  budget_usd: max_usd,
  operational_reserve_per_admission_usd: unit,
  observed_billing_usd: nil,
  input_projection_limit_bytes: 16_384,
  message_limit: 10,
  runtime: %{
    elixir: System.version(),
    otp: to_string(:erlang.system_info(:otp_release)),
    req_llm: to_string(Application.spec(:req_llm, :vsn))
  },
  time_utc: DateTime.utc_now()
}

File.write!(G2.path("manifest.json"), Jason.encode!(manifest, pretty: true))

{:ok, _} =
  Agent.start_link(
    fn -> %{count: 0, reserved_usd: 0.0, max_count: max_count, max_usd: max_usd, unit: unit} end,
    name: G2.Ledger
  )

records =
  Enum.reduce_while(selection, [], fn name, acc ->
    c = Enum.find(G2.cases(), &(elem(&1, 0) == name))

    {model, peer} =
      if live, do: {G2.model(key), nil}, else: G2.TCP.start(G2.TCP.specs(elem(c, 1)))

    record =
      if text_only,
        do: PortableQualification.text(model_id, key, model.base_url),
        else: G2.one(c, model)

    if peer, do: G2.TCP.finish(peer)
    if record.accepted, do: {:cont, acc ++ [record]}, else: {:halt, acc ++ [record]}
  end)

true = PortableQualification.fingerprint() == fingerprint

summary = %{
  accepted: length(records) == length(selection) and Enum.all?(records, & &1.accepted),
  cases: Enum.map(records, &Map.take(&1, [:name, :accepted, :effects, :admissions])),
  ledger: Agent.get(G2.Ledger, & &1),
  live: live,
  observed_billing_usd: nil
}

File.write!(G2.path("summary.json"), Jason.encode!(summary, pretty: true))
IO.puts(Jason.encode!(summary, pretty: true))
if not summary.accepted, do: System.halt(1)

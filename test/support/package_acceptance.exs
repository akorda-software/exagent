# Run with plain elixir, never mix run in the library checkout:
#   elixir test/support/package_acceptance.exs --tar /tmp/preview.tar \
#     --work-dir /tmp/opencode/exagent-night-package-fresh --mode all
# Optional: --lock /absolute/path/mix.lock --seed 771506 --checksum TAR_SHA256
# --prepare-only verifies package bytes and effective tooling destinations without
# downloading/compiling anything; useful with deliberately hostile inherited env.
# Each invocation requires a NEW work directory; each consumer has independent
# package sources, deps, Rebar cache and builds. Only downloaded Hex tooling/cache
# is shared within the invocation. Dependency acquisition needs network access;
# every runtime test is offline (except an ephemeral loopback OTLP receiver).
# Artifacts: input hashes, package file manifest, lock snapshot and per-mode logs,
# resolved graph, compiled provenance, test result and top-level summary.term.

defmodule PackageAcceptance.Runner do
  @modes ~w(none api sdk exporter)
  @tooling_phases ~w(tooling-preflight tooling-hex tooling-rebar)
  @consumer_phases ~w(deps-get compile-edge compile graph smoke)

  def main(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          tar: :string,
          work_dir: :string,
          mode: :string,
          lock: :string,
          seed: :integer,
          checksum: :string,
          prepare_only: :boolean
        ]
      )

    tar = opts |> Keyword.fetch!(:tar) |> Path.expand()
    base = opts |> Keyword.fetch!(:work_dir) |> Path.expand()
    mode = Keyword.get(opts, :mode, "all")
    modes = if mode == "all", do: @modes, else: [mode]
    unless Enum.all?(modes, &(&1 in @modes)), do: raise("mode must be all/none/api/sdk/exporter")

    seed = Keyword.get(opts, :seed, 771_506)
    create_work_dir!(base)

    bytes = File.read!(tar)
    {:ok, outer} = :erl_tar.extract({:binary, bytes}, [:memory])
    outer = Map.new(outer, fn {name, value} -> {to_string(name), value} end)
    version = Map.fetch!(outer, "VERSION")
    metadata = Map.fetch!(outer, "metadata.config")
    contents = Map.fetch!(outer, "contents.tar.gz")
    checksum = sha256(version <> metadata <> contents)
    true = checksum == String.downcase(String.trim(Map.fetch!(outer, "CHECKSUM")))

    if expected = opts[:checksum] do
      unless sha256(bytes) == String.downcase(expected),
        do: raise("unexpected package TAR SHA256: #{sha256(bytes)} (inner #{checksum})")
    end

    {:ok, files} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])
    files = Enum.map(files, fn {name, data} -> {to_string(name), data} end)
    names = Enum.map(files, &elem(&1, 0))
    true = length(names) == length(Enum.uniq(names))

    for {name, _} <- files do
      unless Path.type(name) == :relative and ".." not in Path.split(name),
        do: raise("invalid package member")

      if hd(Path.split(name)) in ~w(test config deps _build .git),
        do: raise("checkout-only directory in package: #{name}")

      if name == "mix.lock", do: raise("package must not rely on checkout lock")

      if String.starts_with?(name, "docs/archive/"),
        do: raise("historical execution records do not belong in the consumer package")
    end

    for required <-
          ~w(mix.exs README.md docs/README.md docs/changelog.md docs/guides/migration.md docs/guides/observability.md LICENSE lib/exagent.ex) do
      unless required in names, do: raise("missing package file: #{required}")
    end

    manifest = Enum.map_join(files, "\n", fn {name, data} -> "#{sha256(data)}  #{name}" end)
    File.write!(Path.join(base, "package-files.sha256"), manifest <> "\n")
    File.write!(Path.join(base, "metadata.config"), metadata)

    lock = if opts[:lock], do: File.read!(Path.expand(opts[:lock]))
    if lock, do: File.write!(Path.join(base, "input.mix.lock"), lock)

    input = %{
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      tar: tar,
      tar_sha256: sha256(bytes),
      hex_checksum: checksum,
      package_file_count: length(files),
      lock_source: opts[:lock],
      lock_sha256: if(lock, do: sha256(lock)),
      elixir: System.version(),
      otp: to_string(:erlang.system_info(:otp_release)),
      seed: seed
    }

    write_term(base, "input.term", input)
    IO.inspect(input, label: "package acceptance input")
    env = isolated_env(base)
    preflight!(base, env)

    if opts[:prepare_only] do
      warnings? = Enum.any?(diagnostics(base, @tooling_phases), &(&1.warning_lines != []))
      System.halt(if warnings?, do: 1, else: 0)
    end

    command!(base, "tooling-hex", ["local.hex", "--force"], env)
    command!(base, "tooling-rebar", ["local.rebar", "--force"], env)
    fixtures = Path.expand("../fixtures/package_acceptance", __DIR__)

    results =
      Enum.map(modes, fn mode ->
        consumer = Path.join(base, mode)
        File.mkdir!(consumer)

        for {name, data} <- files do
          destination = Path.join([consumer, "vendor", "exagent", name])
          File.mkdir_p!(Path.dirname(destination))
          File.write!(destination, data)
        end

        # Templates must not be discovered as tests/Mix projects in the library
        # checkout. Materialize them only inside this disposable consumer.
        for file <- Path.wildcard(Path.join(fixtures, "**/*.template")) do
          relative = file |> Path.relative_to(fixtures) |> String.trim_trailing(".template")
          destination = Path.join(consumer, relative)
          File.mkdir_p!(Path.dirname(destination))
          File.cp!(file, destination)
        end

        if lock, do: File.write!(Path.join(consumer, "mix.lock"), lock)

        mode_env =
          env ++
            [
              {"PACKAGE_ACCEPTANCE_MODE", mode},
              {"PACKAGE_ACCEPTANCE_SEED", to_string(seed)},
              {"MIX_DEPS_PATH", Path.join(consumer, "deps")},
              {"MIX_BUILD_PATH", Path.join(consumer, "_build")},
              {"REBAR_CACHE_DIR", Path.join(consumer, "rebar-cache")},
              {"REBAR_GLOBAL_CONFIG_DIR", Path.join(consumer, "rebar-config")}
            ]

        result =
          try do
            command!(consumer, "deps-get", ["deps.get"], mode_env)

            edge =
              command!(
                consumer,
                "compile-edge",
                ["deps.compile", "exagent", "--include-children"],
                mode_env
              )

            if mode in ["sdk", "exporter"] do
              {sdk, _} = :binary.match(edge, "Compiling opentelemetry\n")
              {agent, _} = :binary.match(edge, "==> exagent")
              unless sdk < agent, do: raise("SDK did not compile before ExAgent")
            end

            command!(consumer, "compile", ["compile", "--warnings-as-errors"], mode_env)
            command!(consumer, "graph", ["run", "--no-start", "graph.exs"], mode_env)

            command!(
              consumer,
              "smoke",
              [
                "test",
                "--warnings-as-errors",
                "--seed",
                to_string(seed)
              ],
              mode_env
            )

            %{mode: mode, status: :passed, path: consumer, runtime_contracts: :passed}
          rescue
            error ->
              message = Exception.message(error)
              IO.puts(:stderr, "#{mode}: #{message}")

              %{
                mode: mode,
                status: :failed,
                path: consumer,
                runtime_contracts: :not_passed,
                error: message
              }
          end

        # Rebar dependencies can warn in compile (not just compile-edge) without
        # failing Mix's consumer-level --warnings-as-errors. Keep runtime evidence
        # separate and diagnose every executed phase, including failed commands.
        diagnostics =
          diagnostics(base, @tooling_phases) ++ diagnostics(consumer, @consumer_phases)

        warnings = Enum.filter(diagnostics, &(&1.warning_lines != []))
        result = Map.put(result, :diagnostics, diagnostics)

        if warnings != [] do
          phases = Enum.map_join(warnings, ", ", & &1.phase)

          IO.puts(
            :stderr,
            "#{mode}: warnings in #{phases}; runtime contracts: #{result.runtime_contracts}"
          )

          Map.merge(result, %{status: :failed, stage: :phase_warnings, warning_phases: phases})
        else
          result
        end
      end)

    write_term(base, "summary.term", %{input: input, consumers: results})
    IO.inspect(results, label: "package acceptance results")
    if Enum.any?(results, &(&1.status == :failed)), do: System.halt(1)
  end

  defp isolated_env(base) do
    # Exporter configuration inherited from the host must never select a remote
    # endpoint or credentials. The fixture sets only a synthetic loopback route.
    scrub = for {key, _} <- System.get_env(), String.starts_with?(key, "OTEL_"), do: {key, nil}

    scrub ++
      [
        {"EXAGENT_OFFLINE", "1"},
        {"MIX_ENV", "test"},
        {"MIX_TARGET", "host"},
        # CLI project selection happens after Mix.start, before even local.hex.
        {"MIX_EXS", nil},
        {"MIX_INSTALL_RESTORE_PROJECT_DIR", nil},
        {"MIX_INSTALL_DIR", Path.join(base, "mix-install")},
        {"MIX_QUIET", nil},
        {"MIX_HOME", Path.join(base, "mix-home")},
        # mise may export MIX_ARCHIVES independently of MIX_HOME. Override both
        # or local.hex can overwrite a different toolchain's global archive.
        {"MIX_ARCHIVES", Path.join(base, "mix-home/archives")},
        {"MIX_ESCRIPTS", Path.join(base, "mix-home/escripts")},
        {"XDG_CACHE_HOME", Path.join(base, "cache")},
        {"XDG_CONFIG_HOME", Path.join(base, "config")},
        {"XDG_DATA_HOME", Path.join(base, "data")},
        {"HEX_HOME", Path.join(base, "hex-home")},
        {"HEX_UNSAFE_HTTPS", "false"},
        {"MIX_REBAR3", nil},
        {"MIX_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"MIX_BUILD_PATH", nil},
        {"REBAR_CACHE_DIR", Path.join(base, "rebar-cache")},
        {"REBAR_GLOBAL_CONFIG_DIR", Path.join(base, "rebar-config")},
        {"ERL_LIBS", nil},
        {"ERL_FLAGS", "+S 4:4"}
      ]
  end

  defp preflight!(base, env) do
    # Query Mix's effective paths in a child before installing any archive. A
    # regression here must fail without mutating the inherited host destinations.
    script =
      project_guard() <>
        """
        Mix.start()
        base = hd(System.argv()) <> "/"
        paths = %{
          mix_home: Mix.Utils.mix_home(), archives: Mix.path_for(:archives),
          escripts: Mix.path_for(:escripts), mix_cache: Mix.Utils.mix_cache(),
          mix_config: Mix.Utils.mix_config(), rebar: Mix.Rebar.local_rebar_path(:rebar3),
          hex_home: System.fetch_env!("HEX_HOME"),
          mix_install: System.fetch_env!("MIX_INSTALL_DIR"),
          rebar_cache: System.fetch_env!("REBAR_CACHE_DIR"),
          rebar_config: System.fetch_env!("REBAR_GLOBAL_CONFIG_DIR")
        }
        for {kind, path} <- paths do
          unless String.starts_with?(Path.expand(path), base), do: raise("non-isolated destination: " <> Atom.to_string(kind) <> " " <> path)
        end
        true = is_nil(System.get_env("MIX_REBAR3"))
        IO.inspect(paths, label: "verified temporary tooling destinations")
        # Exercise the same CLI project-loading boundary as the installation tasks.
        # The new bootstrap directory has no project; an external selector is rejected
        # by the guard before this call can evaluate it.
        Mix.CLI.main(["help"])
        true = is_nil(Mix.Project.get())
        IO.puts("verified effective CLI project: none; target: host; env: test")
        """

    {output, status} =
      System.cmd("elixir", ["-e", script, base], cd: base, env: env, stderr_to_stdout: true)

    record_phase(base, "tooling-preflight", output, status)
    if status != 0, do: raise("tooling isolation preflight failed; see tooling-preflight.log")
  end

  defp command!(cwd, name, args, env) do
    IO.puts("#{cwd}: mix #{Enum.join(args, " ")}")
    # Validate inside EVERY child, before Mix starts or loads a project/config.
    script = project_guard() <> "Mix.CLI.main(System.argv())\n"

    {output, status} =
      System.cmd("elixir", ["-e", script, "--"] ++ args,
        cd: cwd,
        env: env,
        stderr_to_stdout: true
      )

    record_phase(cwd, name, output, status)
    if status != 0, do: raise("mix #{Enum.join(args, " ")} exited #{status}; see #{name}.log")
    output
  end

  defp project_guard do
    """
    for key <- ["MIX_EXS", "MIX_INSTALL_RESTORE_PROJECT_DIR", "MIX_PATH", "MIX_QUIET"] do
      unless is_nil(System.get_env(key)), do: raise("non-isolated selector: " <> key)
    end
    unless System.get_env("MIX_TARGET") == "host", do: raise("non-isolated selector: MIX_TARGET")
    unless System.get_env("MIX_ENV") == "test", do: raise("non-isolated selector: MIX_ENV")
    """
  end

  defp create_work_dir!(base) do
    unless Path.dirname(base) == "/tmp/opencode" and
             String.starts_with?(Path.basename(base), "exagent-night-package"),
           do: raise("work-dir must be a new direct child /tmp/opencode/exagent-night-package*")

    for ancestor <- ["/tmp", "/tmp/opencode"] do
      unless match?({:ok, %File.Stat{type: :directory}}, File.lstat(ancestor)),
        do: raise("work-dir ancestor must be a real directory: #{ancestor}")
    end

    # lstat also detects dangling links. mkdir (not mkdir_p) rejects an existing
    # entry atomically; nothing preexisting is removed or traversed.
    unless File.lstat(base) == {:error, :enoent},
      do: raise("work-dir already exists; use a fresh directory")

    File.mkdir!(base)
  end

  defp record_phase(cwd, name, output, status) do
    log = Path.join(cwd, name <> ".log")
    File.write!(log, output)

    warning_lines =
      output |> String.split("\n") |> Enum.filter(&Regex.match?(~r/\bwarning:/i, &1))

    data = %{
      phase: name,
      exit_status: status,
      log: log,
      warning_lines: warning_lines
    }

    Process.put({__MODULE__, cwd, name}, data)
    # Keep phase diagnostics separate from artifacts written by the command,
    # especially graph.term emitted by the package graph/provenance fixture.
    write_term(cwd, "phase-" <> name <> ".term", data)
  end

  defp diagnostics(cwd, phases) do
    for phase <- phases, data = Process.get({__MODULE__, cwd, phase}), do: data
  end

  defp sha256(data), do: Base.encode16(:crypto.hash(:sha256, data), case: :lower)

  defp write_term(base, name, value),
    do:
      File.write!(
        Path.join(base, name),
        inspect(value, pretty: true, limit: :infinity, printable_limit: :infinity) <> "\n"
      )
end

PackageAcceptance.Runner.main(System.argv())

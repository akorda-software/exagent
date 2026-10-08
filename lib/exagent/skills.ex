defmodule ExAgent.Skills do
  @moduledoc """
  Skills that the model loads on demand (progressive disclosure).

  An agent with many specialised procedures should not send all of them on every
  request. With skills, the model sees a short catalog (name + description) and
  loads a skill's full instructions only when a task needs it:

      skills = ExAgent.Skills.from_dir!(Application.app_dir(:my_app, "priv/skills"))
      agent = ExAgent.new(model: model, instructions: "You are...", skills: skills)

  `ExAgent.new/1` with `:skills` adds:

    * a `load_skill` tool whose description lists the catalog. Its result (the
      skill instructions, plus its file list and newly available tools) becomes
      an ordinary tool return in the history, so a loaded skill stays in context
      across steps, `ExAgent.Server` turns, snapshots and continuations;
    * a `read_skill_file` tool, when a skill has a directory, to read files
      such as `references/forms.md` relative to that directory, never outside it;
    * every skill's `:tools` and, when there are any, an `ExAgent.Skills.Gate`
      before the agent's capabilities that offers them only once their skill has
      been loaded;
    * `ExAgent.Skills.Restore` after the agent's capabilities, which restores
      loaded skills that a compaction capability removed from the request.

  Keeping the catalog in the tool definition leaves `:instructions` and the
  history unchanged, and lets providers cache it with the other tool definitions.
  Changing the skill set changes that definition, like changing any tool. Without
  `:skills`, agents are unaffected.

  ## Directory layout

      priv/skills/
        release-notes/
          SKILL.md
          references/style.md
        incident-report/
          SKILL.md

  A `SKILL.md` starts with YAML frontmatter:

      ---
      name: release-notes
      description: Write release notes. Use when asked to summarise changes for a release.
      ---
      # Release notes
      1. Read references/style.md ...

  This is the format used by other agent harnesses, so the same skills work
  there. See `ExAgent.Skill` for fields and validation rules.

  ## Tools gated by a skill

      skills = ExAgent.Skills.from_dir!(dir, tools: %{"deploy" => DeployTools.tools()})

  The deploy tools are omitted from requests until `deploy` is loaded. They stay
  in the agent inventory, so persisted continuations restore them as usual. A
  tool listed both in `:tools` and in a skill is gated. The gate controls what
  the model is offered; it is not an authority boundary.

  ## Composing by hand

  `tools/2` and `capabilities/1` return the pieces `ExAgent.new/1` adds, for
  example to place a capability that measures the final request after
  `:restore`. Keep `:gate` before capabilities that restrict `function_tools`
  (so they keep the final say) and `:restore` after any compaction capability.

  Skills only add instructions and tools; they do not grant permissions or
  execute skill scripts.
  """

  alias ExAgent.{Skill, Tool}
  alias ExAgent.Message.{Part, Request, Response}

  @load_tool "load_skill"
  @read_tool "read_skill_file"
  @max_file_bytes 262_144
  @max_listed_files 200
  @max_depth 8
  @reserved [@load_tool, @read_tool]
  # Skill tools must not take the default output tool's name either.
  @reserved_skill_tools [@load_tool, @read_tool, "final_result"]
  @skill_file "SKILL.md"
  @max_visited 2_000

  @doc """
  Read every immediate subdirectory of `root` that contains a `SKILL.md`.

  Skills are returned sorted by name. Directories without `SKILL.md` and hidden
  directories are ignored. An invalid skill, a duplicate name or an unreadable
  root fails the whole call.

  Options:

    * `:tools` — map of skill name to its gated `ExAgent.Tool`s.
  """
  @spec from_dir(Path.t(), keyword()) :: {:ok, [Skill.t()]} | {:error, term()}
  def from_dir(root, opts \\ []) when is_list(opts) do
    root = Path.expand(root)
    tools = Map.new(Keyword.get(opts, :tools, %{}))

    with {:ok, entries} <- File.ls(root) |> wrap_root(root) do
      dirs =
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&File.regular?(Path.join(&1, @skill_file)))

      result =
        Enum.reduce_while(dirs, {:ok, []}, fn dir, {:ok, acc} ->
          case Skill.from_dir(dir) do
            {:ok, skill} -> {:cont, {:ok, [skill | acc]}}
            error -> {:halt, error}
          end
        end)

      # Tools are keyed by the frontmatter name, which may differ from the directory.
      with {:ok, skills} <- result,
           [] <- Map.keys(tools) -- Enum.map(skills, & &1.name),
           skills = Enum.map(skills, &%{&1 | tools: Map.get(tools, &1.name, [])}),
           :ok <- validate(skills) do
        {:ok, Enum.sort_by(skills, & &1.name)}
      else
        unknown when is_list(unknown) -> {:error, {:unknown_skill_tools, unknown}}
        error -> error
      end
    end
  end

  defp wrap_root({:error, reason}, root), do: {:error, {:invalid_skills_dir, root, reason}}
  defp wrap_root(ok, _root), do: ok

  @doc "Like `from_dir/2`, raising `ArgumentError` on error."
  @spec from_dir!(Path.t(), keyword()) :: [Skill.t()]
  def from_dir!(root, opts \\ []) do
    case from_dir(root, opts) do
      {:ok, skills} -> skills
      {:error, reason} -> raise ArgumentError, "cannot load skills: #{inspect(reason)}"
    end
  end

  @doc """
  Validate a skill list for an agent: valid skills, unique names, and gated
  tools whose names are unique.
  """
  @spec validate([Skill.t()]) :: :ok | {:error, term()}
  def validate(skills) when is_list(skills) do
    with :ok <-
           Enum.find_value(skills, :ok, fn
             %Skill{} = skill -> with :ok <- Skill.validate(skill), do: nil
             other -> {:error, {:not_a_skill, other}}
           end),
         [] <- duplicates(Enum.map(skills, & &1.name)) do
      names = skills |> Enum.flat_map(& &1.tools) |> Enum.uniq() |> Enum.map(& &1.name)
      duplicated = duplicates(names)

      cond do
        duplicated != [] ->
          {:error, {:duplicate_skill_tools, duplicated}}

        reserved = Enum.find(names, &(&1 in @reserved_skill_tools)) ->
          {:error, {:reserved_tool_name, reserved}}

        true ->
          :ok
      end
    else
      names when is_list(names) -> {:error, {:duplicate_skill_names, names}}
      error -> error
    end
  end

  def validate(other), do: {:error, {:invalid_skills, other}}

  @doc """
  Build the tools added for `skills`: `load_skill`, `read_skill_file` when any
  skill has a `:path`, then each skill's gated tools (deduplicated).

  Options: `:max_file_bytes` (default 256 KiB) bounds both the skill
  instructions returned by `load_skill` and files read by `read_skill_file`.
  """
  @spec tools([Skill.t()], keyword()) :: [Tool.t()]
  def tools(skills, opts \\ []) when is_list(skills) do
    max_bytes = Keyword.get(opts, :max_file_bytes, @max_file_bytes)

    unless is_integer(max_bytes) and max_bytes > 0,
      do: raise(ArgumentError, ":max_file_bytes must be a positive integer")

    with_files = Enum.filter(skills, &is_binary(&1.path))

    read =
      if with_files == [], do: [], else: [read_tool(with_files, max_bytes)]

    gated = skills |> Enum.flat_map(& &1.tools) |> Enum.uniq()
    [load_tool(skills, max_bytes) | read] ++ gated
  end

  @doc """
  Build the capabilities added for `skills`:

    * `:gate` — an `ExAgent.Skills.Gate`, or `nil` when no skill has tools.
      Place it before capabilities that restrict `function_tools`.
    * `:restore` — `ExAgent.Skills.Restore`. Place it after compaction.
  """
  @spec capabilities([Skill.t()]) :: %{gate: ExAgent.Skills.Gate.t() | nil, restore: module()}
  def capabilities(skills) when is_list(skills) do
    gates =
      for skill <- skills, tool <- skill.tools, reduce: %{} do
        acc -> Map.update(acc, tool.name, [skill.name], &Enum.uniq(&1 ++ [skill.name]))
      end

    %{
      gate: if(gates != %{}, do: %ExAgent.Skills.Gate{gates: gates}),
      restore: ExAgent.Skills.Restore
    }
  end

  @doc """
  Names of the skills successfully loaded in `messages`, each once, ordered by
  its most recent load.

  Useful to show which skills a conversation used, for example
  `ExAgent.Skills.loaded(ExAgent.Server.history(server))`.
  """
  @spec loaded([ExAgent.Message.t()]) :: [String.t()]
  def loaded(messages) when is_list(messages) do
    messages |> loaded_returns() |> Enum.map(&elem(&1, 0))
  end

  @doc false
  # Expansion used by ExAgent.new/1. An empty or absent list changes nothing.
  def expand(opts) do
    case Keyword.get(opts, :skills) do
      nil ->
        opts

      [] ->
        opts

      skills ->
        with :ok <- validate(skills),
             tools when is_list(tools) <- Keyword.get(opts, :tools, []),
             added = tools(skills),
             nil <- Enum.find(tools, &clash?(&1, added)),
             caps when is_list(caps) <- Keyword.get(opts, :capabilities, []) do
          %{gate: gate, restore: restore} = capabilities(skills)

          opts
          |> Keyword.put(:tools, tools ++ Enum.reject(added, &(&1 in tools)))
          |> Keyword.put(:capabilities, List.wrap(gate) ++ caps ++ [restore])
        else
          {:error, reason} ->
            raise ArgumentError, "invalid skills: #{inspect(reason)}"

          %Tool{name: name} ->
            raise ArgumentError, "tool name #{name} clashes with :skills"

          other ->
            raise ArgumentError, "invalid tools/capabilities for :skills: #{inspect(other)}"
        end
    end
  end

  # A gated tool may also be listed in :tools (the identical struct appears once);
  # any other tool with the name of a reserved or skill tool is a clash.
  defp clash?(%Tool{name: name} = tool, added),
    do: name in @reserved or Enum.any?(added, &(&1.name == name and &1 != tool))

  defp clash?(_tool, _added), do: false

  @doc false
  # [{skill_name, tool_return_content}] for successful loads, in load order; a
  # later load of the same skill replaces the earlier entry. A return is paired
  # with a call of the immediately preceding Response: some backends reuse
  # tool-call ids across turns, so ids are not unique in a whole history.
  def loaded_returns(messages) do
    load_tool = @load_tool

    {found, _pending} =
      Enum.reduce(messages, {[], %{}}, fn
        %Response{parts: parts}, {found, _pending} ->
          pending =
            for %Part.ToolCall{tool_name: ^load_tool, tool_call_id: id} = call <- parts,
                is_binary(id),
                {:ok, args} <- [Part.ToolCall.args_as_map(call)],
                name = Map.get(args, "name", Map.get(args, :name)),
                is_binary(name),
                into: %{},
                do: {id, name}

          {found, pending}

        %Request{parts: parts}, {found, pending} ->
          loads =
            for %Part.ToolReturn{tool_name: ^load_tool, status: :succeeded} = ret <- parts,
                is_nil(ret.payload_omitted),
                is_binary(ret.content),
                name = pending[ret.tool_call_id],
                is_binary(name),
                do: {name, ret.content}

          {Enum.reverse(loads, found), %{}}

        _other, acc ->
          acc
      end)

    found
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reverse()
  end

  defp load_tool(skills, max_bytes) do
    by_name = Map.new(skills, &{&1.name, &1})

    %Tool{
      name: @load_tool,
      description: catalog(skills),
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{
          "name" => %{
            "type" => "string",
            "enum" => Enum.map(skills, & &1.name),
            "description" => "Name of the skill to load."
          }
        },
        "required" => ["name"],
        "additionalProperties" => false
      },
      takes_ctx: false,
      max_retries: 2,
      call: fn args -> load(Map.fetch!(by_name, arg(args, "name")), max_bytes) end
    }
  end

  defp catalog(skills) do
    entries =
      Enum.map_join(skills, "\n", fn skill ->
        # Gated tools are announced by the load result, not here: naming them
        # before they are offered invites calls the runtime rejects as unknown.
        "- #{skill.name}: #{skill.description |> String.split() |> Enum.join(" ")}"
      end)

    """
    Load a skill: instructions for a specific kind of task.

    When the request matches a skill's description, load that skill before \
    starting the task and follow its instructions. Load only the skills you need. \
    A loaded skill remains available for the rest of the conversation; do not \
    load it again.

    Available skills:
    #{entries}\
    """
  end

  # Read-only, so failures are retries: the model may continue without the skill.
  # The size bound keeps one load from exhausting the history budget.
  defp load(skill, max_bytes) do
    case Skill.instructions(skill) do
      {:ok, body} when byte_size(body) > max_bytes ->
        {:error, %ExAgent.ModelRetry{message: "skill #{skill.name} exceeds #{max_bytes} bytes"}}

      {:ok, body} ->
        {:ok, render(skill, body)}

      {:error, reason} ->
        {:error,
         %ExAgent.ModelRetry{message: "skill #{skill.name} is unavailable: #{inspect(reason)}"}}
    end
  end

  defp render(skill, body) do
    files =
      case list_files(skill.path) do
        {[], _} ->
          ""

        {files, truncated?} ->
          "\n\nSkill files (read with #{@read_tool}, skill \"#{skill.name}\"):\n" <>
            Enum.map_join(files, "\n", &"- #{&1}") <>
            if(truncated?, do: "\n- (list truncated)", else: "")
      end

    tools =
      case skill.tools do
        [] -> ""
        tools -> "\n\nTools now available: #{Enum.map_join(tools, ", ", & &1.name)}"
      end

    ~s(<skill name="#{skill.name}">\n#{body}#{files}#{tools}\n</skill>)
  end

  defp list_files(nil), do: {[], false}

  defp list_files(root) do
    {files, exhausted?} = walk([{"", 0}], root, @max_visited, [])
    files = files |> Enum.reject(&(&1 == @skill_file)) |> Enum.sort()
    {Enum.take(files, @max_listed_files), exhausted? or length(files) > @max_listed_files}
  end

  # Breadth-first over at most @max_visited entries, so a large tree (vendored
  # dependencies, data) costs bounded IO per load. Regular files only; symlinks
  # and hidden entries are not listed.
  defp walk([], _root, _budget, files), do: {files, false}
  defp walk(_queue, _root, budget, files) when budget <= 0, do: {files, true}

  defp walk([{rel, depth} | queue], root, budget, files) do
    entries =
      case File.ls(Path.join(root, rel)) do
        {:ok, entries} -> entries |> Enum.reject(&String.starts_with?(&1, ".")) |> Enum.sort()
        {:error, _} -> []
      end

    {queue, files, budget} =
      Enum.reduce_while(entries, {queue, files, budget}, fn
        _entry, {_queue, _files, budget} = acc when budget <= 0 ->
          {:halt, acc}

        entry, {queue, files, budget} ->
          child = if rel == "", do: entry, else: Path.join(rel, entry)

          case File.lstat(Path.join(root, child)) do
            {:ok, %File.Stat{type: :regular}} ->
              {:cont, {queue, [child | files], budget - 1}}

            {:ok, %File.Stat{type: :directory}} when depth < @max_depth ->
              {:cont, {queue ++ [{child, depth + 1}], files, budget - 1}}

            _ ->
              {:cont, {queue, files, budget - 1}}
          end
      end)

    walk(queue, root, budget, files)
  end

  defp read_tool(skills, max_bytes) do
    by_name = Map.new(skills, &{&1.name, &1})

    %Tool{
      name: @read_tool,
      description:
        "Read a text file of a skill, by its path relative to the skill directory " <>
          "(as listed when the skill was loaded).",
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{
          "skill" => %{"type" => "string", "enum" => Enum.map(skills, & &1.name)},
          "path" => %{
            "type" => "string",
            "description" => "Relative path, for example references/guide.md."
          }
        },
        "required" => ["skill", "path"],
        "additionalProperties" => false
      },
      takes_ctx: false,
      max_retries: 2,
      call: fn args ->
        read_file(Map.fetch!(by_name, arg(args, "skill")), arg(args, "path"), max_bytes)
      end
    }
  end

  defp read_file(skill, path, max_bytes) do
    with {:ok, rel} <- safe_path(skill.path, path),
         full = Path.join(skill.path, rel),
         {:ok, %File.Stat{type: :regular, size: size}} <- File.stat(full),
         true <- size <= max_bytes || {:error, :too_large},
         {:ok, content} <- File.read(full),
         true <- String.valid?(content) || {:error, :binary} do
      {:ok, content}
    else
      {:error, :too_large} ->
        {:error, %ExAgent.ModelRetry{message: "#{path} exceeds #{max_bytes} bytes"}}

      {:error, :binary} ->
        {:error, %ExAgent.ModelRetry{message: "#{path} is not a UTF-8 text file"}}

      _ ->
        {:error,
         %ExAgent.ModelRetry{message: "#{path} is not a readable file of skill #{skill.name}"}}
    end
  end

  # Relative, inside the skill directory after resolving `..` and symlinks, and
  # not hidden (like the file listing).
  defp safe_path(root, path) when is_binary(path) and path != "" do
    with false <- String.contains?(path, <<0>>) or Path.type(path) != :relative,
         {:ok, rel} <- Path.safe_relative(path, root),
         false <- rel |> Path.split() |> Enum.any?(&String.starts_with?(&1, ".")) do
      {:ok, rel}
    else
      _ -> :error
    end
  end

  defp safe_path(_root, _path), do: :error

  # Arguments are validated JSON objects with string keys; atom keys are only
  # accepted when already present (never create or look up atoms from input).
  defp arg(args, key) do
    case Map.fetch(args, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(args, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end

  defp duplicates(names),
    do: names |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1)) |> Enum.map(&elem(&1, 0))
end

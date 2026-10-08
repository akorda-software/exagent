defmodule ExAgent.Skill do
  @moduledoc """
  A skill: instructions for one kind of task, loaded by the model when needed.

  Skills follow the [Agent Skills](https://agentskills.io) layout used by other
  agent harnesses: a directory named after the skill containing a `SKILL.md`
  with YAML frontmatter (`name`, `description`) and a Markdown body, plus
  optional files such as `references/` or `scripts/`. The same directory can
  therefore serve ExAgent and coding agents.

  Only the name and description are advertised up front. The body is returned
  when the model calls `load_skill`, and other files when it reads them. See
  `ExAgent.Skills` for how skills are attached to an agent.

  Fields:

    * `:name` — 1–64 characters: lowercase ASCII letters, digits and single
      hyphens, not starting or ending with a hyphen. Unique per agent.
    * `:description` — non-empty, at most 1024 characters. Say what the skill
      does **and when to use it**; the model decides from this text alone.
    * `:content` — the instructions. When `nil`, they are read from
      `SKILL.md` under `:path` each time the skill is loaded, so edits apply
      without rebuilding the agent.
    * `:path` — the skill directory. Enables `read_skill_file` for its files.
    * `:tools` — `ExAgent.Tool`s offered to the model only after this skill
      is loaded in the conversation.
    * `:frontmatter` — every frontmatter field, best effort and informational.
      Keys are strings; values are strings, lists or maps of strings, and a
      value outside the supported YAML subset is kept as its raw text. Only
      `name` and `description` are interpreted. Fields such as `allowed-tools`
      grant nothing: ExAgent does not take permissions from skill files.

  Skill files are trusted host content, like `:instructions`. ExAgent never
  executes their scripts; expose execution through your own tools.
  """

  alias ExAgent.Skill.Frontmatter
  alias ExAgent.Tool

  defstruct name: nil, description: nil, content: nil, path: nil, tools: [], frontmatter: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          content: String.t() | nil,
          path: Path.t() | nil,
          tools: [Tool.t()],
          frontmatter: %{String.t() => term()}
        }

  @name ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @file_name "SKILL.md"

  @doc """
  Build a skill in code. Raises `ArgumentError` when it is invalid.

      ExAgent.Skill.new(
        name: "release-notes",
        description: "Write release notes. Use when asked to summarise a release.",
        content: "1. List user-visible changes first..."
      )

  Either `:content` or `:path` is required.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    skill = struct!(__MODULE__, opts)

    case validate(skill) do
      :ok -> skill
      {:error, reason} -> raise ArgumentError, "invalid skill: #{inspect(reason)}"
    end
  end

  @doc """
  Parse the text of a `SKILL.md` into a skill whose `:content` is its body.

  Options: `:path` and `:tools` are copied into the skill.
  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse(text, opts \\ []) when is_binary(text) and is_list(opts) do
    with {:ok, yaml, body} <- Frontmatter.split(text),
         {:ok, frontmatter} <- Frontmatter.parse(yaml) do
      skill = %__MODULE__{
        name: frontmatter["name"],
        description: frontmatter["description"],
        content: body,
        path: opts[:path],
        tools: Keyword.get(opts, :tools, []),
        frontmatter: frontmatter
      }

      with :ok <- validate(skill), do: {:ok, skill}
    end
  end

  @doc """
  Read a skill directory containing a `SKILL.md`.

  The frontmatter `name` identifies the skill. The Agent Skills format expects it
  to match the directory name; skills published for other harnesses do not always
  follow that, so a mismatch is accepted.

  The body is not kept: `:content` is `nil`, so the current file is read each
  time the model loads the skill. Option `:tools` attaches gated tools.
  """
  @spec from_dir(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_dir(dir, opts \\ []) when is_list(opts) do
    dir = Path.expand(dir)

    with {:ok, text} <- File.read(Path.join(dir, @file_name)),
         {:ok, skill} <- parse(text, Keyword.put(opts, :path, dir)) do
      {:ok, %{skill | content: nil}}
    else
      {:error, reason} -> {:error, {:invalid_skill, dir, reason}}
    end
  end

  @doc """
  Return the skill's current instructions: `:content`, or the body of its
  `SKILL.md` read now.
  """
  @spec instructions(t()) :: {:ok, String.t()} | {:error, term()}
  def instructions(%__MODULE__{content: content}) when is_binary(content), do: {:ok, content}

  def instructions(%__MODULE__{path: path} = skill) when is_binary(path) do
    with {:ok, text} <- File.read(Path.join(path, @file_name)),
         {:ok, current} <- parse(text) do
      if current.name == skill.name, do: {:ok, current.content}, else: {:error, :name_changed}
    end
  end

  @doc "Check a skill's fields. Returns `:ok` or `{:error, reason}`."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = skill) do
    cond do
      not is_binary(skill.name) or byte_size(skill.name) > 64 or
          not Regex.match?(@name, skill.name) ->
        {:error, {:invalid_name, skill.name}}

      not is_binary(skill.description) or not String.valid?(skill.description) or
        String.trim(skill.description) == "" or String.contains?(skill.description, <<0>>) ->
        {:error, :missing_description}

      String.length(skill.description) > 1024 ->
        {:error, :description_too_long}

      not (is_binary(skill.content) and String.valid?(skill.content)) and
          not is_binary(skill.path) ->
        {:error, :missing_content}

      not is_list(skill.tools) or
          not Enum.all?(skill.tools, &match?(%Tool{name: n} when is_binary(n), &1)) ->
        {:error, :invalid_tools}

      true ->
        :ok
    end
  end
end

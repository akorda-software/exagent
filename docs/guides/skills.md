# Skills

A skill packages the instructions for one kind of task. The model sees only
each skill's name and description, and loads the full instructions when a task
needs them. An agent can therefore carry many procedures without sending all of
them on every request.

ExAgent reads the [Agent Skills](https://agentskills.io) directory format used
by other agent harnesses, so the same `SKILL.md` files can serve your
application and your coding agents.

## Write a skill

A skill is a directory with a `SKILL.md`. The frontmatter's `name` and
`description` form the catalog entry. The Markdown body holds the instructions:

```text
priv/skills/
  release-notes/
    SKILL.md
    references/style.md
  incident-report/
    SKILL.md
```

```markdown
---
name: release-notes
description: Write release notes. Use when asked to summarise changes for a release.
---
# Release notes

1. Group user-visible changes first; read references/style.md for tone.
2. ...
```

Write the description for the model: say what the skill does **and when to use
it**. Names use lowercase letters, digits and single hyphens (at most 64
characters). Descriptions are at most 1024 characters.

## Attach skills to an agent

```elixir
skills = ExAgent.Skills.from_dir!(Application.app_dir(:my_app, "priv/skills"))

agent =
  ExAgent.new(
    model: model,
    instructions: "You are the release assistant.",
    skills: skills
  )
```

`:skills` adds a `load_skill` tool whose description lists the catalog. When the
model calls it, the result contains the skill's instructions and a list of its
other files. That result is an ordinary tool return, so the skill stays in the
conversation:

- for the rest of the run;
- on later `ExAgent.Server` turns;
- in snapshots and continuations.

`ExAgent.Skills.loaded/1` lists the skills a conversation has loaded. For a
LiveView, call `ExAgent.Skills.loaded(ExAgent.Server.history(server))` after a
turn, or watch tool events whose tool name is `load_skill`.

`SKILL.md` is read again on each load, so edits apply without restarting. The
catalog is built with the agent; rebuild the agent to add or remove skills. If a
load fails (the file was removed, or its instructions exceed the size limit),
the model receives a retry message and can continue without that skill.

Skills can also be defined in code:

```elixir
ExAgent.Skill.new(
  name: "refund-policy",
  description: "Refund rules. Use when a customer asks for a refund.",
  content: "Refunds within 30 days need ..."
)
```

## Read skill files

When a skill comes from a directory, the agent also gets `read_skill_file`. It
reads a UTF-8 text file by its path relative to that skill directory. The load
result lists up to 200 files and marks the list when it is truncated. The
following are rejected:

- absolute paths;
- paths that leave the directory through `..` or a symlink;
- hidden files or directories (names starting with `.`), which are also left
  out of the file list;
- binary files and files over the size limit.

Each rejection reaches the model as a retry so it can correct the path. As with
any tool, repeated failures beyond the tool's retry budget end the run.

ExAgent does not execute skill scripts. If a skill needs to run code, expose that
operation as your own tool, with your own permissions and limits.

## Unlock tools with a skill

A skill can carry tools that the model sees only after loading it:

```elixir
skills =
  ExAgent.Skills.from_dir!(dir,
    tools: %{"deploy" => DeployTools.tools()}
  )
```

The keys are skill names from the frontmatter. Until `deploy` is loaded, an
`ExAgent.Skills.Gate` omits its tools from model requests, so they cannot be
executed. The catalog does not name them; the load result announces them. A call
made before loading is treated like a call to any tool the request did not
offer. With the default retry budget, that ends the run. The tools remain in the
agent's tool inventory, so persisted continuations restore them as usual.

The gate runs before the agent's own capabilities. A capability that removes a
tool from `function_tools` therefore keeps the final say, even after the skill
is loaded. A capability that rebuilds the tool set from the agent inventory can
also offer gated tools early. The gate decides what the model is offered; it is
not an authority boundary. Use `ExAgent.Permissions` for that.

A tool listed both in `:tools` and in a skill is gated. A different tool with
the same name as a skill tool raises `ArgumentError`. So does a tool named
`load_skill` or `read_skill_file` when `:skills` is used.

## Compaction

When an `ExAgent.Compaction.Capability` summarises older messages, a loaded
skill's instructions could otherwise be summarised away. `ExAgent.Skills.Restore`
runs after the agent's own capabilities. If the request projection no longer
contains a loaded skill, it puts that skill's instructions back as one
user-level message. That message goes in the same position as a compaction
summary: before the first message that is not instructions-only. When the first
request carries both the instructions and the prompt, that position comes before
it. The stored history is never modified. The restored text is added after the
compaction threshold was evaluated.

## Compose it yourself

`ExAgent.Skills.tools/2` and `ExAgent.Skills.capabilities/1` return the pieces
that `:skills` adds. Use them to:

- change the order, for example to place a capability that measures the final
  request after `:restore`;
- change `:max_file_bytes` (default 256 KiB), which bounds both the loaded
  instructions and files read with `read_skill_file`.

Keep `:gate` before capabilities that restrict tools, and `:restore` after
compaction.

## Limits

- The catalog is part of the `load_skill` tool definition. Each description adds
  tokens to every request. Write descriptions to be concise.
- The frontmatter reader supports the YAML used by skill metadata. Unsupported
  constructs in `name` or `description` are an error. Malformed structure, such
  as a top-level line that is not a `key:`, is also an error. Other fields are
  best effort: strings, lists or maps of strings, or the raw text of a value
  outside the subset.
- Skill names follow the Agent Skills rule. The frontmatter `name` identifies the
  skill even when it differs from the directory name.
- `allowed-tools` and other frontmatter fields are informational. Skills never
  grant permissions; use `ExAgent.Permissions` and your own tools for that.
- Skill content is trusted host content, like `:instructions`. Do not load skills
  from untrusted sources.

API: `ExAgent.Skills`, `ExAgent.Skill`, `ExAgent.Skills.Gate`,
`ExAgent.Skills.Restore`.

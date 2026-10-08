defmodule ExAgent.SkillsTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Server, Skill, Skills, Tool}
  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test
  alias ExAgent.Skill.Frontmatter

  @moduletag :tmp_dir

  defp write_skill(root, name, frontmatter, body, files \\ %{}) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "SKILL.md"), "---\n#{frontmatter}\n---\n#{body}\n")

    for {path, content} <- files do
      File.mkdir_p!(Path.dirname(Path.join(dir, path)))
      File.write!(Path.join(dir, path), content)
    end

    dir
  end

  defp call(name, args, id), do: %Part.ToolCall{tool_name: name, args: args, tool_call_id: id}

  # A scripted step that reports the tools and messages of the request it sees.
  defp observe(pid, item) do
    fn messages, params ->
      send(pid, {:request, Enum.map(params.function_tools, & &1.name), messages})
      item
    end
  end

  # The model was asked to correct the call (argument validation or ModelRetry).
  defp corrected?(messages, name) do
    Enum.any?(messages, fn
      %Request{parts: parts} ->
        Enum.any?(parts, fn
          %Part.Retry{tool_name: ^name} -> true
          %Part.ToolReturn{tool_name: ^name, status: :validation_error} -> true
          _ -> false
        end)

      _ ->
        false
    end)
  end

  defp returns(messages, name) do
    for %Request{parts: parts} <- messages,
        %Part.ToolReturn{tool_name: ^name} = ret <- parts,
        do: ret
  end

  defp echo_tool(name) do
    Tool.new(
      name: name,
      description: "Echo for #{name}.",
      parameters_json_schema: %{"type" => "object", "properties" => %{}},
      takes_ctx: false,
      call: fn _ -> {:ok, "#{name} ran"} end
    )
  end

  describe "frontmatter" do
    test "reads plain, quoted, block and nested values as strings" do
      yaml = """
      # comment
      name: pdf-forms
      description: >
        Fill PDF forms.
        Use when a form is attached.

        Second paragraph.
      license: "Apache-2.0" # trailing comment
      quoted: 'it''s fine'
      escaped: "line\\nnext \\u00e9"
      literal: |-
        a
          b
      continued: first part
        second part
      version: 1.0
      metadata:
        author: someone
        enabled: true
      allowed-tools:
        - Read
        - "Bash(git:*)"
      empty:
      """

      assert {:ok, map} = Frontmatter.parse(yaml)
      assert map["name"] == "pdf-forms"

      assert map["description"] ==
               "Fill PDF forms. Use when a form is attached.\nSecond paragraph.\n"

      assert map["license"] == "Apache-2.0"
      assert map["quoted"] == "it's fine"
      assert map["escaped"] == "line\nnext é"
      assert map["literal"] == "a\n  b"
      assert map["continued"] == "first part second part"
      assert map["version"] == "1.0"
      assert map["metadata"] == %{"author" => "someone", "enabled" => "true"}
      assert map["allowed-tools"] == ["Read", "Bash(git:*)"]
      assert map["empty"] == nil
    end

    test "reads nested mappings, flow and indentless sequences" do
      yaml = """
      platforms: [linux, macos, windows]
      none: []
      metadata:
        hermes:
          tags: [cron, jobs]
          related:
            - one
            - two
      tools:
      - Read
      - Write
      summary:
        Starts on the next line
        and continues.
      """

      assert {:ok, map} = Frontmatter.parse(yaml)
      assert map["platforms"] == ["linux", "macos", "windows"]
      assert map["none"] == []

      assert map["metadata"] == %{
               "hermes" => %{"tags" => ["cron", "jobs"], "related" => ["one", "two"]}
             }

      assert map["tools"] == ["Read", "Write"]
      assert map["summary"] == "Starts on the next line and continues."
    end

    test "keeps optional fields outside the subset verbatim" do
      yaml = """
      name: a
      base: &anchor x
      flow: {a: 1}
      metadata:
        {
          "k": "v"
        }
      items:
        - key: value
      quoted_list: ["a, b"]
      """

      assert {:ok, map} = Frontmatter.parse(yaml)
      assert map["name"] == "a"
      assert map["base"] == "&anchor x"
      assert map["flow"] == "{a: 1}"
      assert "{\n" <> _ = map["metadata"]
      assert map["items"] == "- key: value"
      assert map["quoted_list"] == ~s(["a, b"])
      assert {:ok, _} = Jason.encode(map)
    end

    test "rejects name/description outside the subset and broken structure" do
      assert {:error, {:unsupported_frontmatter, 2}} = Frontmatter.parse("name: &a x")

      assert {:error, {:unsupported_frontmatter, 3}} =
               Frontmatter.parse("a: 1\ndescription: \"\\q\"")

      assert {:error, {:unsupported_frontmatter, 3}} =
               Frontmatter.parse("description: \"x\"\n  continued")

      assert {:error, {:duplicate_frontmatter_key, 3}} = Frontmatter.parse("a: 1\na: 2")
      assert {:error, {:unsupported_frontmatter, 2}} = Frontmatter.parse("  indented: x")
      assert {:error, {:unsupported_frontmatter, 3}} = Frontmatter.parse("a: 1\nnot a key")
    end

    test "folds multi-line plain scalars like YAML and rejects malformed blocks" do
      assert {:ok, %{"a" => "one two\nthree", "b" => "x y"}} =
               Frontmatter.parse("a: one\n  two\n\n  three\nb: x\n  y # note")

      assert {:ok, %{"opt" => "a\n  # c\n  b"}} = Frontmatter.parse("opt: a\n  # c\n  b")

      assert {:error, {:unsupported_frontmatter, 3}} =
               Frontmatter.parse("description: a\n  # c\n  b")

      assert {:error, {:unsupported_frontmatter, 4}} =
               Frontmatter.parse("description: |\n    x\n  y")
    end

    test "keeps line breaks around more-indented lines of folded blocks" do
      assert {:ok, %{"d" => "a\n  indented\nb\n"}} =
               Frontmatter.parse("d: >\n  a\n    indented\n  b")

      assert {:ok, "n: x", "    code\ntext"} =
               Frontmatter.split("---\nn: x\n---\n\n    code\ntext\n")
    end

    test "splits the frontmatter from the body, accepting CRLF and a BOM" do
      text = "\uFEFF---\r\nname: x\r\n---\r\n\r\n# Body\r\n"
      assert {:ok, "name: x", "# Body"} = Frontmatter.split(text)
      assert {:ok, "name: x", "Body"} = Frontmatter.split("--- \nname: x\n---\nBody")
      assert {:error, :missing_frontmatter} = Frontmatter.split("# no frontmatter")
      assert {:error, :unterminated_frontmatter} = Frontmatter.split("---\nname: x\n")
    end
  end

  describe "Skill" do
    test "parse/2 validates the Agent Skills name and description rules" do
      ok = "---\nname: my-skill-2\ndescription: Does things.\n---\nBody"
      assert {:ok, %Skill{name: "my-skill-2", content: "Body"}} = Skill.parse(ok)

      for name <- ["My-Skill", "-lead", "trail-", "double--hyphen", "with space", ""] do
        text = "---\nname: \"#{name}\"\ndescription: d\n---\nBody"
        assert {:error, {:invalid_name, _}} = Skill.parse(text)
      end

      long = String.duplicate("a", 65)

      assert {:error, {:invalid_name, _}} =
               Skill.parse("---\nname: #{long}\ndescription: d\n---\n")

      assert {:error, :missing_description} = Skill.parse("---\nname: a\n---\nBody")

      too_long = String.duplicate("x", 1025)

      assert {:error, :description_too_long} =
               Skill.parse("---\nname: a\ndescription: #{too_long}\n---\n")
    end

    test "new/1 raises on invalid skills and requires content or a path" do
      assert %Skill{} = Skill.new(name: "a", description: "d", content: "c")
      assert_raise ArgumentError, fn -> Skill.new(name: "a", description: "d") end
      assert_raise ArgumentError, fn -> Skill.new(name: "A", description: "d", content: "c") end
    end

    test "from_dir/2 identifies the skill by its frontmatter name", %{tmp_dir: tmp} do
      dir = write_skill(tmp, "other-name", "name: a-skill\ndescription: d", "Body")
      assert {:ok, %Skill{name: "a-skill", path: ^dir, content: nil}} = Skill.from_dir(dir)
      assert {:ok, "Body"} = Skill.instructions(elem(Skill.from_dir(dir), 1))
    end
  end

  describe "Skills.from_dir/2 errors" do
    test "duplicate names across directories and a missing root are errors", %{tmp_dir: tmp} do
      write_skill(tmp, "one", "name: same\ndescription: A.", "A")
      write_skill(tmp, "two", "name: same\ndescription: B.", "B")
      assert {:error, {:duplicate_skill_names, ["same"]}} = Skills.from_dir(tmp)

      missing = Path.join(tmp, "missing")
      assert {:error, {:invalid_skills_dir, ^missing, :enoent}} = Skills.from_dir(missing)
    end
  end

  describe "Skills.from_dir/2" do
    test "reads skill subdirectories sorted by name, ignoring others", %{tmp_dir: tmp} do
      write_skill(tmp, "zeta", "name: zeta\ndescription: Z.", "Z body")
      write_skill(tmp, "alpha", "name: alpha\ndescription: A.", "A body")
      File.mkdir_p!(Path.join(tmp, "not-a-skill"))
      write_skill(tmp, ".hidden", "name: hidden\ndescription: H.", "H")

      assert {:ok, [%Skill{name: "alpha", content: nil, path: path}, %Skill{name: "zeta"}]} =
               Skills.from_dir(tmp)

      assert path == Path.join(tmp, "alpha")
    end

    test "attaches gated tools by frontmatter name, not directory name", %{tmp_dir: tmp} do
      write_skill(tmp, "deploy-v2", "name: deploy\ndescription: D.", "Body")
      tool = echo_tool("ship")

      assert [%Skill{name: "deploy", tools: [^tool]}] =
               Skills.from_dir!(tmp, tools: %{"deploy" => [tool]})

      assert {:error, {:unknown_skill_tools, ["deploy-v2"]}} =
               Skills.from_dir(tmp, tools: %{"deploy-v2" => [tool]})
    end

    test "attaches gated tools by name and rejects unknown names", %{tmp_dir: tmp} do
      write_skill(tmp, "deploy", "name: deploy\ndescription: D.", "Body")
      tool = echo_tool("ship")

      assert [%Skill{tools: [^tool]}] = Skills.from_dir!(tmp, tools: %{"deploy" => [tool]})

      assert {:error, {:unknown_skill_tools, ["missing"]}} =
               Skills.from_dir(tmp, tools: %{"missing" => [tool]})

      broken = write_skill(tmp, "broken", "name: broken", "Body")
      assert {:error, {:invalid_skill, ^broken, :missing_description}} = Skills.from_dir(tmp)
      assert_raise ArgumentError, fn -> Skills.from_dir!(tmp) end
    end
  end

  describe "ExAgent.new/1 with :skills" do
    test "adds a load tool with the catalog and leaves instructions untouched" do
      skills = [
        Skill.new(name: "alpha", description: "First\n  skill.", content: "A"),
        Skill.new(name: "beta", description: "Second.", content: "B", tools: [echo_tool("go")])
      ]

      agent = ExAgent.new(model: "test", instructions: "Base.", skills: skills)
      plain = ExAgent.new(model: "test", instructions: "Base.")

      assert agent.instructions == plain.instructions
      assert Enum.map(agent.tools, & &1.name) == ["load_skill", "go"]

      assert [%ExAgent.Skills.Gate{gates: %{"go" => ["beta"]}}, ExAgent.Skills.Restore] =
               agent.capabilities

      [load | _] = agent.tools
      assert load.description =~ "- alpha: First skill."
      assert String.ends_with?(load.description, "- alpha: First skill.\n- beta: Second.")
      assert load.parameters_json_schema["properties"]["name"]["enum"] == ["alpha", "beta"]
    end

    test "an empty or absent skill list builds the same agent" do
      assert ExAgent.new(model: "test", skills: []) == ExAgent.new(model: "test")
    end

    test "invalid skill lists raise ArgumentError" do
      skill = Skill.new(name: "a", description: "d", content: "c")
      assert_raise ArgumentError, fn -> ExAgent.new(model: "test", skills: [skill, skill]) end
      assert_raise ArgumentError, fn -> ExAgent.new(model: "test", skills: [:nope]) end

      clash = [
        %{skill | tools: [echo_tool("x")]},
        Skill.new(
          name: "b",
          description: "d",
          content: "c",
          tools: [%{echo_tool("x") | max_retries: 3}]
        )
      ]

      assert_raise ArgumentError, fn -> ExAgent.new(model: "test", skills: clash) end
    end

    test "the gate runs before user capabilities and the restore after them" do
      skill = Skill.new(name: "a", description: "d", content: "c")
      agent = ExAgent.new(model: "test", capabilities: [Identity], skills: [skill])
      assert [Identity, ExAgent.Skills.Restore] = agent.capabilities

      gated = %{skill | tools: [echo_tool("x")]}
      agent = ExAgent.new(model: "test", capabilities: [Identity], skills: [gated])
      assert [%ExAgent.Skills.Gate{}, Identity, ExAgent.Skills.Restore] = agent.capabilities
    end

    test "tool names used by :skills are reserved" do
      skill = Skill.new(name: "a", description: "d", content: "c")

      assert_raise ArgumentError, ~r/clashes/, fn ->
        ExAgent.new(model: "test", tools: [echo_tool("load_skill")], skills: [skill])
      end

      assert_raise ArgumentError, ~r/reserved_tool_name/, fn ->
        ExAgent.new(model: "test", skills: [%{skill | tools: [echo_tool("read_skill_file")]}])
      end
    end
  end

  describe "tools listed both in :tools and in a skill" do
    test "the identical tool appears once and is gated" do
      tool = echo_tool("ship")
      skill = Skill.new(name: "a", description: "d", content: "c", tools: [tool])
      agent = ExAgent.new(model: "test", tools: [tool], skills: [skill])
      assert Enum.map(agent.tools, & &1.name) == ["ship", "load_skill"]
      assert [%ExAgent.Skills.Gate{gates: %{"ship" => ["a"]}}, _] = agent.capabilities
    end

    test "a different tool with the same name raises" do
      skill = Skill.new(name: "a", description: "d", content: "c", tools: [echo_tool("ship")])

      assert_raise ArgumentError, ~r/clashes/, fn ->
        ExAgent.new(
          model: "test",
          tools: [%{echo_tool("ship") | max_retries: 3}],
          skills: [skill]
        )
      end
    end
  end

  describe "loading during a run" do
    test "returns the instructions as a tool result the next request sees", %{tmp_dir: tmp} do
      write_skill(tmp, "notes", "name: notes\ndescription: Write notes.", "Use bullet points.", %{
        "references/style.md" => "Be brief.",
        ".secret" => "hidden"
      })

      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "notes"}, "c1")]},
          observe(pid, "done")
        ]
      }

      agent = ExAgent.new(model: model, skills: Skills.from_dir!(tmp))
      assert {:ok, result} = ExAgent.run(agent, "Write notes")
      assert result.output == "done"

      assert_receive {:request, _tools, messages}

      assert [%Part.ToolReturn{status: :succeeded, content: content}] =
               returns(messages, "load_skill")

      assert content =~ ~s(<skill name="notes">\nUse bullet points.)
      assert content =~ "- references/style.md"
      refute content =~ ".secret"
      refute content =~ "description:"
      assert Skills.loaded(result.messages) == ["notes"]
    end

    test "reads SKILL.md again on each load", %{tmp_dir: tmp} do
      dir = write_skill(tmp, "live", "name: live\ndescription: L.", "Version one.")
      [skill] = Skills.from_dir!(tmp)

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "live"}, "c1")]},
          fn _messages, _params ->
            File.write!(
              Path.join(dir, "SKILL.md"),
              "---\nname: live\ndescription: L.\n---\nVersion two."
            )

            {:tool_calls, [call("load_skill", %{"name" => "live"}, "c2")]}
          end,
          "done"
        ]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: [skill]), "go")
      [first, second] = returns(result.messages, "load_skill")
      assert first.content =~ "Version one."
      assert second.content =~ "Version two."
    end

    test "rejects names outside the catalog through argument validation" do
      skill = Skill.new(name: "a", description: "d", content: "c")

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "other"}, "c1")]},
          "done"
        ]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: [skill]), "go")
      assert Skills.loaded(result.messages) == []
      assert corrected?(result.messages, "load_skill")
    end

    test "a load that fails at run time unlocks nothing", %{tmp_dir: tmp} do
      dir = write_skill(tmp, "gone", "name: gone\ndescription: G.", "Body")
      [skill] = Skills.from_dir!(tmp, tools: %{"gone" => [echo_tool("gone_tool")]})
      File.rm!(Path.join(dir, "SKILL.md"))
      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "gone"}, "c1")]},
          observe(pid, "done")
        ]
      }

      # The model is asked to continue without the skill; the run goes on.
      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: [skill]), "go")
      assert Skills.loaded(result.messages) == []
      assert corrected?(result.messages, "load_skill")
      assert_receive {:request, tools, _}
      refute "gone_tool" in tools
    end
  end

  describe "gated tools" do
    test "are offered only after their skill is loaded" do
      gated = echo_tool("deploy_now")

      skill =
        Skill.new(name: "deploy", description: "Deploys.", content: "Steps.", tools: [gated])

      pid = self()

      model = %Test{
        script: [
          observe(pid, {:tool_calls, [call("load_skill", %{"name" => "deploy"}, "c1")]}),
          observe(pid, {:tool_calls, [call("deploy_now", %{}, "c2")]}),
          observe(pid, "done")
        ]
      }

      agent = ExAgent.new(model: model, tools: [echo_tool("always")], skills: [skill])
      assert {:ok, result} = ExAgent.run(agent, "deploy")

      assert_receive {:request, before, _}
      assert_receive {:request, unlocked, _}
      assert_receive {:request, ^unlocked, _}
      assert before == ["always", "load_skill"]
      assert unlocked == ["always", "load_skill", "deploy_now"]

      assert [%Part.ToolReturn{status: :succeeded, content: "deploy_now ran"}] =
               returns(result.messages, "deploy_now")

      [load] = returns(result.messages, "load_skill")
      assert load.content =~ "Tools now available: deploy_now"
    end

    test "a later capability that removes a gated tool keeps the final say" do
      skill =
        Skill.new(
          name: "deploy",
          description: "D.",
          content: "S.",
          tools: [echo_tool("deploy_now")]
        )

      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "deploy"}, "c1")]},
          observe(pid, "done")
        ]
      }

      agent =
        ExAgent.new(model: model, capabilities: [ExAgent.SkillsTest.ReadOnly], skills: [skill])

      assert {:ok, _} = ExAgent.run(agent, "go")
      assert_receive {:request, ["load_skill"], _}
    end

    test "loads are paired with their own response when backends reuse call ids" do
      alpha =
        Skill.new(name: "alpha", description: "A.", content: "A.", tools: [echo_tool("a_tool")])

      beta =
        Skill.new(name: "beta", description: "B.", content: "B.", tools: [echo_tool("b_tool")])

      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "alpha"}, "call_0")]},
          {:tool_calls, [call("load_skill", %{"name" => "beta"}, "call_0")]},
          observe(pid, "done")
        ]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: [alpha, beta]), "go")
      assert Skills.loaded(result.messages) == ["alpha", "beta"]
      assert_receive {:request, ["load_skill", "a_tool", "b_tool"], _}
    end

    test "cannot be executed before their skill is loaded" do
      skill =
        Skill.new(
          name: "deploy",
          description: "D.",
          content: "S.",
          tools: [echo_tool("deploy_now")]
        )

      model = %Test{script: [{:tool_calls, [call("deploy_now", %{}, "c1")]}, "done"]}

      # Same outcome as any tool absent from the request: never invoked.
      assert {:error, %ExAgent.RunError{reason: reason, partial: %{messages: messages}}} =
               ExAgent.run(ExAgent.new(model: model, skills: [skill]), "go")

      assert {:unexpected_model_behavior,
              {:tool_retries_exhausted, "deploy_now", {:unknown_tool, "deploy_now"}}} = reason

      refute Enum.any?(returns(messages, "deploy_now"), &(&1.status == :succeeded))
    end

    test "stay unlocked on later Server turns" do
      skill =
        Skill.new(
          name: "deploy",
          description: "D.",
          content: "S.",
          tools: [echo_tool("deploy_now")]
        )

      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "deploy"}, "c1")]},
          "loaded",
          observe(pid, "second turn")
        ]
      }

      agent = ExAgent.new(model: model, skills: [skill])
      server = start_supervised!({Server, agent: agent})

      assert {:ok, %{output: "loaded"}} = Server.chat(server, "load it")
      assert {:ok, %{output: "second turn"}} = Server.chat(server, "again")
      assert_receive {:request, ["load_skill", "deploy_now"], _}
    end

    test "stay unlocked after a Server rehydrates from its snapshot" do
      skill =
        Skill.new(
          name: "deploy",
          description: "D.",
          content: "S.",
          tools: [echo_tool("deploy_now")]
        )

      id = "skills-#{System.unique_integer([:positive])}"
      store = {ExAgent.Store.ETS, ExAgent.Store.ETS}
      on_exit(fn -> ExAgent.Store.delete_agent_snapshot(store, id) end)
      pid = self()

      first = %Test{
        script: [{:tool_calls, [call("load_skill", %{"name" => "deploy"}, "c1")]}, "loaded"]
      }

      {:ok, a} =
        Server.start_link(
          agent: ExAgent.new(model: first, skills: [skill]),
          agent_id: id,
          store: :ets
        )

      assert {:ok, %{output: "loaded"}} = Server.chat(a, "load it")
      :ok = GenServer.stop(a, :normal)

      second = %Test{
        script: [observe(pid, {:tool_calls, [call("deploy_now", %{}, "c2")]}), "shipped"]
      }

      {:ok, b} =
        Server.start_link(
          agent: ExAgent.new(model: second, skills: [skill]),
          agent_id: id,
          store: :ets
        )

      assert {:ok, %{output: "shipped"}} = Server.chat(b, "ship")
      assert_receive {:request, ["load_skill", "deploy_now"], _}
      assert [%Part.ToolReturn{status: :succeeded}] = returns(Server.history(b), "deploy_now")
      GenServer.stop(b)
    end
  end

  describe "read_skill_file" do
    setup %{tmp_dir: tmp} do
      root = Path.join(tmp, "skills")
      outside = Path.join(tmp, "outside.txt")
      File.write!(outside, "secret")

      dir =
        write_skill(root, "docs", "name: docs\ndescription: D.", "Body", %{
          "references/guide.md" => "Guide text.",
          "big.txt" => String.duplicate("x", 300_000),
          "image.bin" => <<0xFF, 0xFE, 0x00>>,
          ".env" => "TOKEN=x",
          "sub/.hidden.md" => "hidden"
        })

      outside_dir = Path.join(tmp, "outside-dir")
      File.mkdir_p!(outside_dir)
      File.write!(Path.join(outside_dir, "x.txt"), "secret")
      File.ln_s!(outside, Path.join(dir, "link.txt"))
      File.ln_s!(outside_dir, Path.join(dir, "linked"))
      %{skills: Skills.from_dir!(root)}
    end

    defp read(skills, path) do
      model = %Test{
        script: [
          {:tool_calls, [call("read_skill_file", %{"skill" => "docs", "path" => path}, "r1")]},
          "done"
        ]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: skills), "read")
      result.messages
    end

    test "reads a text file relative to the skill directory", %{skills: skills} do
      assert [%Part.ToolReturn{status: :succeeded, content: "Guide text."}] =
               returns(read(skills, "references/guide.md"), "read_skill_file")
    end

    test "accepts .. that stays inside the directory", %{skills: skills} do
      assert [%Part.ToolReturn{status: :succeeded, content: "Guide text."}] =
               returns(read(skills, "references/../references/guide.md"), "read_skill_file")
    end

    test "rejects paths outside the directory, hidden, binary and large files", %{
      skills: skills
    } do
      for path <- [
            "../outside.txt",
            "/etc/hostname",
            "link.txt",
            "missing.md",
            "big.txt",
            "image.bin",
            "linked/x.txt",
            ".env",
            "sub/.hidden.md",
            "references/../.env"
          ] do
        messages = read(skills, path)

        assert [%Part.ToolReturn{status: :validation_error, content: reason}] =
                 returns(messages, "read_skill_file"),
               path

        assert reason =~ path or reason =~ "UTF-8" or reason =~ "exceeds", path
      end
    end

    test "serves files of several directory skills", %{tmp_dir: tmp} do
      root = Path.join(tmp, "multi")
      write_skill(root, "one", "name: one\ndescription: O.", "B", %{"a.md" => "from one"})
      write_skill(root, "two", "name: two\ndescription: T.", "B", %{"a.md" => "from two"})

      model = %Test{
        script: [
          {:tool_calls,
           [
             call("read_skill_file", %{"skill" => "one", "path" => "a.md"}, "r1"),
             call("read_skill_file", %{"skill" => "two", "path" => "a.md"}, "r2")
           ]},
          "done"
        ]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: Skills.from_dir!(root)), "go")

      assert ["from one", "from two"] =
               result.messages |> returns("read_skill_file") |> Enum.map(& &1.content)
    end

    test "the file list is bounded and marked when truncated", %{tmp_dir: tmp} do
      files = Map.new(1..205, &{"data/f#{&1}.txt", "x"})
      write_skill(tmp, "big", "name: big\ndescription: B.", "Body", files)
      [skill] = Skills.from_dir!(tmp)

      model = %Test{
        script: [{:tool_calls, [call("load_skill", %{"name" => "big"}, "c1")]}, "done"]
      }

      {:ok, result} = ExAgent.run(ExAgent.new(model: model, skills: [skill]), "go")
      [%Part.ToolReturn{content: content}] = returns(result.messages, "load_skill")
      assert content =~ "- (list truncated)"
      assert length(Regex.scan(~r/^- data\//m, content)) == 200
    end

    test "is not added when no skill has a directory" do
      agent =
        ExAgent.new(model: "test", skills: [Skill.new(name: "a", description: "d", content: "c")])

      refute Enum.any?(agent.tools, &(&1.name == "read_skill_file"))
    end
  end

  describe "compaction" do
    test "a loaded skill removed from the projection is restored after the instructions" do
      skill = Skill.new(name: "notes", description: "N.", content: "Use bullet points.")
      pid = self()

      compaction = %ExAgent.Compaction.Capability{
        compactor: ExAgent.Compaction.Summary,
        opts: [threshold_tokens: 0, keep_recent: 0, summarize: fn _old -> "earlier work" end]
      }

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "notes"}, "c1")]},
          {:tool_calls, [call("noop", %{}, "c2")]},
          observe(pid, "done")
        ]
      }

      agent =
        ExAgent.new(
          model: model,
          instructions: "Base.",
          tools: [echo_tool("noop")],
          capabilities: [compaction],
          skills: [skill]
        )

      assert {:ok, result} = ExAgent.run(agent, "write")
      assert_receive {:request, _tools, messages}

      assert returns(messages, "load_skill") == []
      texts = for %Request{parts: parts} <- messages, %Part.User{content: c} <- parts, do: c
      assert Enum.any?(texts, &(&1 =~ "Summary of earlier conversation"))
      restored = Enum.find(texts, &(&1 =~ "Skills loaded earlier"))
      assert restored =~ ~s(<skill name="notes">\nUse bullet points.)

      # Same position as the summary: before the first message that is not
      # instructions-only (here the first request carries instructions + prompt).
      position = fn text -> Enum.find_index(messages, &(inspect(&1) =~ text)) end
      assert position.("Skills loaded earlier") < position.("Summary of earlier conversation")
      assert position.("Summary of earlier conversation") < position.("Base.")

      # The canonical history keeps the original exchange and gains nothing.
      assert [%Part.ToolReturn{}] = returns(result.messages, "load_skill")
      refute Enum.any?(result.messages, &(inspect(&1) =~ "Skills loaded earlier"))
    end

    test "several loaded skills are restored in one message" do
      skills = [
        Skill.new(name: "one", description: "O.", content: "First body."),
        Skill.new(name: "two", description: "T.", content: "Second body.")
      ]

      pid = self()

      compaction = %ExAgent.Compaction.Capability{
        compactor: ExAgent.Compaction.Summary,
        opts: [threshold_tokens: 0, keep_recent: 0, summarize: fn _old -> "earlier" end]
      }

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "one"}, "c1")]},
          {:tool_calls, [call("load_skill", %{"name" => "two"}, "c2")]},
          observe(pid, "done")
        ]
      }

      agent = ExAgent.new(model: model, capabilities: [compaction], skills: skills)
      assert {:ok, _} = ExAgent.run(agent, "go")
      assert_receive {:request, _tools, messages}

      assert [restored] =
               for(
                 %Request{parts: parts} <- messages,
                 %Part.User{content: c} <- parts,
                 String.starts_with?(c, "Skills loaded earlier"),
                 do: c
               )

      assert restored =~ "First body." and restored =~ "Second body."
    end

    test "nothing is inserted when the projection still holds the skill" do
      skill = Skill.new(name: "notes", description: "N.", content: "Body.")
      pid = self()

      model = %Test{
        script: [
          {:tool_calls, [call("load_skill", %{"name" => "notes"}, "c1")]},
          observe(pid, "done")
        ]
      }

      agent =
        ExAgent.new(model: model, capabilities: [ExAgent.SkillsTest.Identity], skills: [skill])

      assert {:ok, _} = ExAgent.run(agent, "write")
      assert_receive {:request, _tools, messages}
      refute Enum.any?(messages, &(inspect(&1) =~ "Skills loaded earlier"))
      assert [_] = returns(messages, "load_skill")
    end
  end

  defmodule ReadOnly do
    use ExAgent.Capability
    @impl true
    def before_model_request(_cap, state) do
      tools = Enum.reject(state.params.function_tools, &(&1.name == "deploy_now"))
      %{state | params: %{state.params | function_tools: tools}}
    end
  end

  defmodule Identity do
    use ExAgent.Capability
    @impl true
    def before_model_request(_cap, state), do: %{state | request_messages: state.messages}
  end
end

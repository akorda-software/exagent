# Parse source only. Never evaluate a release's project or application code.
defmodule DocumentationRuntimeIdentity do
  @documentation_attributes [:moduledoc, :doc, :typedoc]
  @project_documentation_functions [:docs, :docs_head, :docs_footer]

  def run(tag) do
    paths =
      git!([
        "ls-tree",
        "-r",
        "--name-only",
        tag,
        "--",
        "lib",
        "examples",
        "config",
        "mix.lock",
        ".formatter.exs"
      ])

    paths = String.split(paths, "\n", trim: true)

    current =
      git!([
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "lib",
        "examples",
        "config",
        "mix.lock",
        ".formatter.exs"
      ])

    current = current |> String.split("\n", trim: true) |> Enum.sort()
    unless paths == current, do: raise("runtime file inventory changed")

    for path <- paths do
      original = git!(["show", tag <> ":" <> path])
      updated = File.read!(path)

      cond do
        String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex") ->
          compare_ast!(path, original, updated, false)

        Path.basename(path) == "README.md" ->
          :ok

        original != updated ->
          raise("runtime/dependency input changed: #{path}")

        true ->
          :ok
      end
    end

    compare_ast!("mix.exs", git!(["show", tag <> ":mix.exs"]), File.read!("mix.exs"), true)
    IO.puts("Runtime source, project/dependency contracts and input inventory match #{tag}.")
  end

  defp compare_ast!(path, original, updated, project?) do
    {old_code, old_dynamic_docs} = normalized(original, project?)
    {new_code, new_dynamic_docs} = normalized(updated, project?)

    unless old_code == new_code and old_dynamic_docs == new_dynamic_docs,
      do: raise("executable source changed: #{path}")
  end

  defp normalized(source, project?) do
    {ast, dynamic} = top_level(Code.string_to_quoted!(source), [], project?)
    {metadata_free(ast), Enum.reverse(dynamic)}
  end

  defp top_level({:__block__, metadata, entries}, dynamic, project?) do
    {entries, dynamic} = Enum.map_reduce(entries, dynamic, &top_level(&1, &2, project?))
    {{:__block__, metadata, entries}, dynamic}
  end

  defp top_level({:defmodule, metadata, [name, [do: body]]}, dynamic, project?) do
    entries =
      case body do
        {:__block__, _, entries} -> entries
        entry -> [entry]
      end

    {entries, dynamic} = Enum.map_reduce(entries, dynamic, &module_entry(&1, &2, project?))
    entries = Enum.reject(entries, &(&1 == :__documentation_removed__))
    {{:defmodule, metadata, [name, [do: {:__block__, [], entries}]]}, dynamic}
  end

  defp top_level(node, dynamic, _project?), do: {node, dynamic}

  defp module_entry({:@, _, [{attribute, _, [value]}]}, dynamic, _project?)
       when attribute in @documentation_attributes do
    dynamic = if Macro.quoted_literal?(value), do: dynamic, else: [metadata_free(value) | dynamic]
    {:__documentation_removed__, dynamic}
  end

  defp module_entry({:defp, _, [{name, _, args} = head, _body]}, dynamic, true)
       when name in @project_documentation_functions and (is_list(args) or is_nil(args)) do
    {{:__project_documentation__, [], [metadata_free(head)]}, dynamic}
  end

  defp module_entry(node, dynamic, project?) do
    # Do not descend into function/macro bodies: quoted @doc is executable data.
    top_level(node, dynamic, project?)
  end

  defp metadata_free(ast) do
    Macro.prewalk(ast, fn
      {name, metadata, args} when is_list(metadata) -> {name, [], args}
      other -> other
    end)
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {_output, _} -> raise("git source read failed")
    end
  end
end

case System.argv() do
  [tag] -> DocumentationRuntimeIdentity.run(tag)
  _ -> raise("usage: documentation_runtime_identity.exs STABLE_TAG")
end

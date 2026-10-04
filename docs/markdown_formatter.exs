defmodule ExAgent.Docs.Markdown do
  @moduledoc false

  # ExDoc's public custom-formatter callback. Keep stock generation, then rebase
  # source-relative links for flattened Markdown. No changes to ExDoc, runtime
  # code, source snippets or the HTML/EPUB formatters.
  def run(config, modules, extras) do
    config = %{
      config
      | description:
          "ExAgent #{config.version}: usage guides and public API reference. " <>
            (config.description || "")
    }

    result = apply(ExDoc.Formatter.MARKDOWN, :run, [config, modules, extras])
    sources = Map.new(extras, &{Path.expand(&1.source_path), &1.id <> ".md"})
    pages = MapSet.new(Enum.map(extras ++ modules, &(&1.id <> ".html")))

    for extra <- extras do
      path = Path.join(config.output, extra.id <> ".md")
      File.write!(path, rebase(extra.source_doc, extra.source_path, sources, pages))
    end

    # Module documentation can reference extras by repository path (including
    # ExAgent's README-derived moduledoc). Rebase those stock Markdown files too.
    for module <- modules do
      path = Path.join(config.output, module.id <> ".md")

      File.write!(
        path,
        rebase(File.read!(path), module.source_path || "README.md", sources, pages)
      )
    end

    result
  end

  # Tooling regression seam; this module never enters lib/.
  def rebase(markdown, source_path, sources, pages) do
    {lines, _fence} =
      markdown
      |> String.split("\n")
      |> Enum.map_reduce(nil, fn line, fence ->
        marker = Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, line)

        cond do
          marker && is_nil(fence) ->
            [_, opening] = marker
            {line, opening}

          marker && fence && closes?(line, fence) ->
            {line, nil}

          fence ->
            {line, fence}

          true ->
            {rebase_line(line, source_path, sources, pages), nil}
        end
      end)

    Enum.join(lines, "\n")
  end

  defp closes?(line, fence) do
    marker = String.first(fence)
    pattern = "^\\s{0,3}" <> marker <> "{" <> to_string(String.length(fence)) <> ",}\\s*$"
    Regex.match?(Regex.compile!(pattern), line)
  end

  defp rebase_line(line, source, sources, pages) do
    if Regex.match?(~r/^\[[^\]]+\]:\s*/, line) do
      rebase_text(line, source, sources, pages)
    else
      ~r/(`+[^`]*`+)/
      |> Regex.split(line, include_captures: true)
      |> Enum.map_join(fn part ->
        if String.starts_with?(part, "`"),
          do: part,
          else: rebase_text(part, source, sources, pages)
      end)
    end
  end

  defp rebase_text(text, source, sources, pages) do
    rewrite = &destination(&1, source, sources, pages)

    text =
      Regex.replace(~r/(\]\()([^\s)]+)(?=[\s)])/, text, fn _, prefix, path ->
        prefix <> rewrite.(path)
      end)

    text =
      Regex.replace(~r/^(\[[^\]]+\]:\s*)(\S+)/, text, fn _, prefix, path ->
        prefix <> rewrite.(path)
      end)

    Regex.replace(~r/(href=")([^"]+)(")/, text, fn _, prefix, path, suffix ->
      prefix <> rewrite.(path) <> suffix
    end)
  end

  defp destination(path, source, sources, pages) do
    uri = URI.parse(path)

    if uri.scheme || uri.host || is_nil(uri.path) || uri.path == "" do
      path
    else
      original = Path.expand(URI.decode(uri.path), Path.dirname(Path.expand(source)))

      target =
        Map.get(sources, original) ||
          Map.get(sources, Path.expand(URI.decode(uri.path))) ||
          if(MapSet.member?(pages, uri.path), do: String.replace_suffix(uri.path, ".html", ".md"))

      if target, do: URI.to_string(%{uri | path: target}), else: path
    end
  end
end

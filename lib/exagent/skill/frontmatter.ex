defmodule ExAgent.Skill.Frontmatter do
  @moduledoc false
  # Reads the YAML frontmatter of an Agent Skills `SKILL.md` without adding a
  # YAML dependency to every consumer. Supported: block mappings and sequences
  # nested to any depth, plain/quoted/block (`|`/`>`) scalars, plain scalars
  # continued on indented lines and flow sequences of plain scalars. Scalars stay
  # strings; no booleans/numbers are inferred. Other constructs (flow mappings,
  # anchors, tags, sequences of mappings) are never guessed: in `name` or
  # `description` they are an error with the line number; in any other top-level
  # field the value is kept as its raw YAML text.

  @key ~r/^([A-Za-z0-9_][A-Za-z0-9_.\-]*)[ \t]*:(?:[ \t]+(.*)|[ \t]*)$/
  @double ~r/^"((?:[^"\\]|\\.)*)"[ \t]*(?:#.*)?$/
  @single ~r/^'((?:[^']|'')*)'[ \t]*(?:#.*)?$/
  @block ~r/^([|>])([+-]?)[ \t]*(?:#.*)?$/

  @doc false
  @spec split(String.t()) :: {:ok, String.t(), String.t()} | {:error, term()}
  def split(text) when is_binary(text) do
    text = text |> String.trim_leading("﻿") |> String.replace("\r\n", "\n")

    with [first | rest] <- String.split(text, "\n"),
         "---" <- String.trim_trailing(first) do
      case Enum.split_while(rest, &(String.trim_trailing(&1) not in ["---", "..."])) do
        {_yaml, []} ->
          {:error, :unterminated_frontmatter}

        {yaml, [_close | body]} ->
          # Leading blank lines go; indentation of the first body line stays.
          body = body |> Enum.drop_while(&(String.trim(&1) == "")) |> Enum.join("\n")
          {:ok, Enum.join(yaml, "\n"), String.trim_trailing(body)}
      end
    else
      _ -> {:error, :missing_frontmatter}
    end
  end

  @doc false
  @spec parse(String.t()) :: {:ok, %{String.t() => term()}} | {:error, term()}
  def parse(yaml) when is_binary(yaml) do
    yaml
    |> String.split("\n")
    |> Enum.with_index(2)
    |> top(%{})
  end

  @required ~w(name description)

  defp top([], acc), do: {:ok, acc}

  defp top([{line, n} | rest], acc) do
    cond do
      ignorable?(line) ->
        top(rest, acc)

      indent(line) > 0 or String.starts_with?(line, "\t") ->
        unsupported(n)

      true ->
        with [_, key | raw] <- Regex.run(@key, line),
             false <- Map.has_key?(acc, key) do
          raw = String.trim(List.first(raw, ""))
          {children, rest} = children(rest, 0, raw)

          case value(raw, children, n) do
            {:ok, value} ->
              top(rest, Map.put(acc, key, value))

            {:error, _} = error when key in @required ->
              error

            # Optional fields outside the subset are kept verbatim, not guessed.
            {:error, _} ->
              text = Enum.map_join([raw | Enum.map(children, &elem(&1, 0))], "\n", & &1)
              top(rest, Map.put(acc, key, String.trim(text)))
          end
        else
          true -> {:error, {:duplicate_frontmatter_key, n}}
          _ -> unsupported(n)
        end
    end
  end

  # Lines that belong to an entry at `margin`: blank or more indented, plus
  # same-indent `- item` lines when the entry has no inline value (YAML allows
  # `key:` followed by an unindented sequence).
  defp children(lines, margin, raw) do
    indentless? = raw == "" or String.starts_with?(raw, "#")

    Enum.split_while(lines, fn {line, _} ->
      blank?(line) or indent(line) > margin or
        (indentless? and indent(line) == margin and sequence_item?(line))
    end)
  end

  defp value(raw, children, n) do
    cond do
      Regex.match?(@block, raw) ->
        [_, style, chomp] = Regex.run(@block, raw)
        block(children, style, chomp)

      raw == "" or String.starts_with?(raw, "#") ->
        collection(children)

      String.starts_with?(raw, "[") ->
        if Enum.all?(children, &ignorable?(elem(&1, 0))), do: flow(raw, n), else: unsupported(n)

      true ->
        with {:ok, value} <- scalar(raw, n), do: continuation(value, raw, children)
    end
  end

  # A quoted value must close on its own line. A plain value may continue on
  # more indented lines: they fold with single spaces and each blank line becomes
  # a newline, as in YAML. A comment line ends a plain scalar, so one followed by
  # more text is outside the subset.
  defp continuation(value, raw, children) do
    lines = children |> Enum.reverse() |> Enum.drop_while(&blank?(elem(&1, 0))) |> Enum.reverse()

    cond do
      lines == [] ->
        {:ok, value}

      quoted?(raw) ->
        unsupported(elem(hd(lines), 1))

      comment = Enum.find(lines, &comment?(elem(&1, 0))) ->
        unsupported(elem(comment, 1))

      true ->
        rest = Enum.map(lines, &(&1 |> elem(0) |> String.trim() |> strip_comment()))
        {:ok, fold([value | rest])}
    end
  end

  defp collection(lines) do
    case Enum.reject(lines, &ignorable?(elem(&1, 0))) do
      [] ->
        {:ok, nil}

      [{first, n} | _] ->
        margin = indent(first)
        [_ | more] = lines = Enum.drop_while(lines, &ignorable?(elem(&1, 0)))
        text = String.trim(first)

        cond do
          sequence_item?(first) ->
            sequence(lines, margin, [])

          Regex.match?(@key, text) and not quoted?(text) ->
            mapping(lines, margin, %{})

          # `key:` followed by an indented multi-line scalar.
          true ->
            with {:ok, value} <- scalar(text, n), do: continuation(value, text, more)
        end
    end
  end

  defp sequence([], _margin, acc), do: {:ok, Enum.reverse(acc)}

  defp sequence([{line, n} | rest], margin, acc) do
    cond do
      ignorable?(line) ->
        sequence(rest, margin, acc)

      indent(line) != margin or not sequence_item?(line) ->
        unsupported(n)

      true ->
        "-" <> item = String.trim_leading(line)
        item = String.trim(item)

        {children, rest} =
          Enum.split_while(rest, &(blank?(elem(&1, 0)) or indent(elem(&1, 0)) > margin))

        # A sequence of mappings (`- key: value`) is outside the subset.
        with false <- Regex.match?(@key, item) and not quoted?(item),
             {:ok, value} <- value(item, children, n) do
          sequence(rest, margin, [value | acc])
        else
          true -> unsupported(n)
          error -> error
        end
    end
  end

  defp mapping([], _margin, acc), do: {:ok, acc}

  defp mapping([{line, n} | rest], margin, acc) do
    if ignorable?(line) do
      mapping(rest, margin, acc)
    else
      with true <- indent(line) == margin,
           [_, key | raw] <- Regex.run(@key, String.trim_leading(line)),
           false <- Map.has_key?(acc, key),
           raw = String.trim(List.first(raw, "")),
           {children, rest} = children(rest, margin, raw),
           {:ok, value} <- value(raw, children, n) do
        mapping(rest, margin, Map.put(acc, key, value))
      else
        {:error, _} = error -> error
        _ -> unsupported(n)
      end
    end
  end

  # Flow sequences of plain scalars only, such as `[linux, macos]`.
  defp flow(raw, n) do
    case Regex.run(~r/^\[([^\[\]{}"']*)\][ \t]*(?:#.*)?$/, raw) do
      [_, inner] ->
        items = inner |> String.split(",") |> Enum.map(&String.trim/1)

        case items do
          [""] ->
            {:ok, []}

          _ ->
            if "" in Enum.drop(items, -1),
              do: unsupported(n),
              else: {:ok, Enum.reject(items, &(&1 == ""))}
        end

      nil ->
        unsupported(n)
    end
  end

  defp scalar("", _n), do: {:ok, nil}

  defp scalar(raw, n) do
    cond do
      match = Regex.run(@double, raw) -> unescape(Enum.at(match, 1), n)
      match = Regex.run(@single, raw) -> {:ok, String.replace(Enum.at(match, 1), "''", "'")}
      String.first(raw) in ~w(" ' [ { & * ! % @ ` | >) -> unsupported(n)
      true -> {:ok, strip_comment(raw)}
    end
  end

  @escapes %{"\\" => "\\", "\"" => "\"", "/" => "/", "n" => "\n", "t" => "\t", "r" => "\r"}

  defp unescape(text, n) do
    Regex.split(~r/\\(u[0-9A-Fa-f]{4}|.)/, text, include_captures: true)
    |> Enum.reduce_while({:ok, ""}, fn
      "\\u" <> hex, {:ok, acc} when byte_size(hex) == 4 ->
        case Integer.parse(hex, 16) do
          {code, ""} when code not in 0xD800..0xDFFF -> {:cont, {:ok, acc <> <<code::utf8>>}}
          _ -> {:halt, unsupported(n)}
        end

      "\\" <> char, {:ok, acc} ->
        case Map.fetch(@escapes, char) do
          {:ok, value} -> {:cont, {:ok, acc <> value}}
          :error -> {:halt, unsupported(n)}
        end

      part, {:ok, acc} ->
        {:cont, {:ok, acc <> part}}
    end)
  end

  defp block(nested, style, chomp) do
    margin =
      case Enum.find(nested, &(not blank?(elem(&1, 0)))) do
        nil -> 0
        {line, _} -> indent(line)
      end

    case Enum.find(nested, fn {line, _} -> not blank?(line) and indent(line) < margin end) do
      {_, n} ->
        unsupported(n)

      nil ->
        lines =
          Enum.map(nested, fn {line, _} ->
            if blank?(line), do: "", else: String.slice(line, margin..-1//1)
          end)

        {content, trailing} = split_trailing(lines)

        text =
          case style do
            "|" -> Enum.join(content, "\n")
            ">" -> fold(content)
          end

        {:ok,
         cond do
           content == [] -> ""
           chomp == "-" -> text
           chomp == "+" -> text <> "\n" <> String.duplicate("\n", length(trailing))
           true -> text <> "\n"
         end}
    end
  end

  defp split_trailing(lines) do
    trailing = lines |> Enum.reverse() |> Enum.take_while(&(&1 == ""))
    {Enum.drop(lines, -length(trailing)), trailing}
  end

  # YAML folding: consecutive normal lines join with a space and each empty line
  # between them is a newline. Breaks next to more-indented lines are kept.
  defp fold(lines) do
    {text, _kind, _blanks} =
      lines
      |> Enum.chunk_by(&fold_kind/1)
      |> Enum.reduce({"", nil, 0}, fn chunk, {acc, previous, blanks} ->
        case fold_kind(hd(chunk)) do
          :empty ->
            {acc, previous, blanks + length(chunk)}

          kind ->
            separator =
              cond do
                previous == nil -> String.duplicate("\n", blanks)
                kind == :normal and previous == :normal -> String.duplicate("\n", blanks)
                true -> String.duplicate("\n", blanks + 1)
              end

            joiner = if kind == :more, do: "\n", else: " "
            {acc <> separator <> Enum.join(chunk, joiner), kind, 0}
        end
      end)

    text
  end

  defp fold_kind(""), do: :empty
  defp fold_kind(" " <> _), do: :more
  defp fold_kind("\t" <> _), do: :more
  defp fold_kind(_), do: :normal

  defp strip_comment(text),
    do: text |> String.split(~r/[ \t]#/, parts: 2) |> hd() |> String.trim_trailing()

  defp comment?(line), do: String.starts_with?(String.trim_leading(line), "#")

  defp sequence_item?(line) do
    case String.trim_leading(line) do
      "-" -> true
      "- " <> _ -> true
      "-\t" <> _ -> true
      _ -> false
    end
  end

  defp quoted?(text), do: String.first(text) in ["\"", "'"]
  defp ignorable?(line), do: blank?(line) or comment?(line)
  defp blank?(line), do: String.trim(line) == ""
  defp indent(line), do: byte_size(line) - byte_size(String.trim_leading(line, " "))
  defp unsupported(n), do: {:error, {:unsupported_frontmatter, n}}
end

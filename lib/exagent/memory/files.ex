defmodule ExAgent.Memory.Files do
  @moduledoc false
  # Pure memory commands over one scope's files: `%{"/memories/a.md" => text}`.
  # Directories are implicit (a path prefix of some file). Every command returns
  # `{:read, text}`, `{:write, files, text}` or `{:error, text}`; texts are written
  # for the model.

  @root "/memories"
  @max_path_bytes 255
  @max_segment_bytes 100
  @max_depth 8

  @type files :: %{String.t() => String.t()}
  @type limits :: %{
          max_file_bytes: pos_integer(),
          max_total_bytes: pos_integer(),
          max_files: pos_integer()
        }

  @spec root() :: String.t()
  def root, do: @root

  @doc false
  @spec run(files(), map(), limits(), boolean()) ::
          {:read, String.t()} | {:write, files(), String.t()} | {:error, String.t()}
  def run(files, %{"command" => "view"} = args, _limits, _read_only), do: view(files, args)

  def run(_files, %{"command" => command}, _limits, true) when is_binary(command),
    do: {:error, "Memory is read-only here; only the view command is available."}

  def run(files, %{"command" => "create"} = args, limits, _),
    do: write(files, limits, fn -> create(files, args) end)

  def run(files, %{"command" => "str_replace"} = args, limits, _),
    do: write(files, limits, fn -> str_replace(files, args) end)

  def run(files, %{"command" => "insert"} = args, limits, _),
    do: write(files, limits, fn -> insert(files, args) end)

  def run(files, %{"command" => "delete"} = args, _limits, _), do: delete(files, args)

  def run(files, %{"command" => "rename"} = args, _limits, _), do: rename(files, args)

  def run(_files, %{"command" => command}, _limits, _) when is_binary(command),
    do:
      {:error,
       "Unknown command #{inspect(command)}. Use view, create, str_replace, insert, delete or rename."}

  def run(_files, _args, _limits, _), do: {:error, "`command` is required."}

  # ----- paths ----------------------------------------------------------------

  @doc false
  @spec path(term()) :: {:ok, String.t()} | {:error, String.t()}
  def path(path) when is_binary(path) do
    # One spelling per name: composed and decomposed accents are the same file.
    path = if String.valid?(path), do: :unicode.characters_to_nfc_binary(path), else: path
    trimmed = String.trim_trailing(path, "/")

    cond do
      not String.valid?(path) or byte_size(path) > @max_path_bytes ->
        {:error, "Invalid path: use at most #{@max_path_bytes} bytes of text."}

      trimmed == @root ->
        {:ok, @root}

      String.starts_with?(trimmed, @root <> "/") ->
        segments = trimmed |> String.replace_prefix(@root <> "/", "") |> String.split("/")

        if length(segments) <= @max_depth and Enum.all?(segments, &segment?/1),
          do: {:ok, @root <> "/" <> Enum.join(segments, "/")},
          else: {:error, "Invalid path #{inspect(path)}: #{path_rules()}"}

      true ->
        {:error, "Invalid path #{inspect(path)}: paths must start with /memories."}
    end
  end

  def path(nil), do: {:error, "`path` is required."}
  def path(_), do: {:error, "`path` must be a string."}

  defp path_rules,
    do:
      "use names separated by single slashes, at most #{@max_depth} levels, " <>
        "without '.', '..', hidden names, control characters or < > \" characters."

  defp segment?(segment) do
    segment != "" and byte_size(segment) <= @max_segment_bytes and
      not String.starts_with?(segment, ".") and
      not String.contains?(segment, ["\\", "<", ">", "\""]) and
      not Regex.match?(~r/[\p{C}\p{Zl}\p{Zp}]/u, segment)
  end

  @doc false
  @spec valid_files?(term()) :: boolean()
  def valid_files?(files) when is_map(files) do
    Enum.all?(files, fn {path, text} ->
      is_binary(path) and is_binary(text) and String.valid?(text) and
        match?({:ok, ^path}, path(path)) and path != @root and is_nil(parent_file(files, path))
    end)
  end

  def valid_files?(_), do: false

  # ----- view -----------------------------------------------------------------

  defp view(files, args) do
    with {:ok, path} <- path(args["path"]) do
      cond do
        Map.has_key?(files, path) -> view_file(path, Map.fetch!(files, path), args["view_range"])
        dir?(files, path) -> {:read, listing(files, path)}
        true -> missing(path)
      end
    end
  end

  defp view_file(path, text, range) do
    lines = String.split(text, "\n")
    count = length(lines)

    with {:ok, first, last} <- view_range(range, count) do
      numbered =
        lines
        |> Enum.with_index(1)
        |> Enum.slice((first - 1)..(last - 1)//1)
        |> Enum.map_join("\n", fn {line, n} ->
          String.pad_leading(Integer.to_string(n), 6) <> "\t" <> line
        end)

      body = if text == "", do: "(empty file)", else: numbered
      {:read, "Here's the content of #{path} with line numbers:\n" <> body}
    end
  end

  defp view_range(nil, count), do: {:ok, 1, count}

  defp view_range([first, last], count) when is_integer(first) and is_integer(last) do
    last = if last == -1, do: count, else: last

    if first >= 1 and first <= count and last >= first and last <= count,
      do: {:ok, first, last},
      else:
        {:error,
         "Invalid view_range: the file has #{count} lines; use [start, end] with " <>
           "1 <= start <= end <= #{count}, or end -1 for the last line."}
  end

  defp view_range(_, _), do: {:error, "view_range must be [start_line, end_line]."}

  defp listing(files, dir) do
    prefix = dir <> "/"

    entries =
      files
      |> Enum.filter(fn {path, _} -> String.starts_with?(path, prefix) end)
      |> Enum.map(fn {path, text} ->
        rest = binary_part(path, byte_size(prefix), byte_size(path) - byte_size(prefix))
        {String.split(rest, "/"), byte_size(text)}
      end)

    if entries == [] do
      "The directory #{dir} is empty."
    else
      lines =
        entries
        |> Enum.flat_map(fn
          {[name], size} -> [{[name], {:file, size}}]
          {[d, name], size} -> [{[d], :dir}, {[d, name], {:file, size}}]
          {[d, sub | _], _} -> [{[d], :dir}, {[d, sub], :dir}]
        end)
        |> Enum.reduce(%{}, fn
          {key, {:file, size}}, acc ->
            Map.put(acc, key, {:file, size})

          {key, :dir}, acc ->
            Map.update(acc, key, {:dir, 1}, fn {:dir, n} -> {:dir, n + 1} end)
        end)
        |> Enum.sort_by(fn {key, _} -> key end)
        |> Enum.map(fn
          {key, {:file, size}} -> "- #{prefix}#{Enum.join(key, "/")} (#{size} bytes)"
          {key, {:dir, _}} -> "- #{prefix}#{Enum.join(key, "/")}/"
        end)

      "Files and directories in #{dir} (up to 2 levels):\n" <> Enum.join(lines, "\n")
    end
  end

  # ----- writes -----------------------------------------------------------------

  defp write(files, limits, fun) do
    with {:write, new_files, text} <- fun.(),
         :ok <- within_limits(files, new_files, limits) do
      {:write, new_files, text}
    end
  end

  defp within_limits(old, new, limits) do
    changed = Enum.filter(new, fn {path, text} -> Map.get(old, path) != text end)
    total = new |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum()

    cond do
      Enum.any?(changed, fn {path, text} ->
        byte_size(text) > limits.max_file_bytes and
            byte_size(text) > byte_size(Map.get(old, path, ""))
      end) ->
        {:error,
         "A memory file may hold at most #{limits.max_file_bytes} bytes. " <>
           "Keep files concise or split the content."}

      map_size(new) > max(map_size(old), limits.max_files) ->
        {:error,
         "Memory may hold at most #{limits.max_files} files. Merge or delete obsolete files first."}

      total > limits.max_total_bytes and total > total_bytes(old) ->
        {:error,
         "Memory is full: #{total} of #{limits.max_total_bytes} bytes. " <>
           "Condense or delete obsolete content first."}

      true ->
        :ok
    end
  end

  defp total_bytes(files), do: files |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum()

  defp create(files, args) do
    with {:ok, path} <- path(args["path"]),
         {:ok, text} <- string(args, "file_text"),
         :ok <- creatable(files, path) do
      verb = if Map.has_key?(files, path), do: "overwritten", else: "created"
      {:write, Map.put(files, path, text), "File #{verb} successfully at: #{path}"}
    end
  end

  defp creatable(_files, @root),
    do: {:error, "#{@root} is the memory directory; create a file inside it."}

  defp creatable(files, path) do
    cond do
      dir?(files, path) ->
        {:error, "#{path} is a directory."}

      parent_file(files, path) ->
        {:error, "#{parent_file(files, path)} is a file, not a directory."}

      true ->
        :ok
    end
  end

  defp str_replace(files, args) do
    with {:ok, path} <- path(args["path"]),
         {:ok, text} <- file(files, path),
         {:ok, old} <- string(args, "old_str"),
         :ok <- if(old == "", do: {:error, "old_str must not be empty."}, else: :ok),
         {:ok, new} <- optional_string(args, "new_str") do
      case :binary.matches(text, old) do
        [] ->
          {:error, "No replacement was performed: old_str did not appear verbatim in #{path}."}

        [{at, _}] ->
          size = byte_size(old)

          updated =
            binary_part(text, 0, at) <>
              new <> binary_part(text, at + size, byte_size(text) - at - size)

          {:write, Map.put(files, path, updated), "The memory file #{path} has been edited."}

        matches ->
          lines = Enum.map_join(matches, ", ", fn {at, _} -> line_of(text, at) end)

          {:error,
           "No replacement was performed: old_str appears #{length(matches)} times in " <>
             "#{path} (lines #{lines}). Include more context so it is unique."}
      end
    end
  end

  defp line_of(text, at),
    do: text |> binary_part(0, at) |> :binary.matches("\n") |> length() |> Kernel.+(1)

  defp insert(files, args) do
    with {:ok, path} <- path(args["path"]),
         {:ok, text} <- file(files, path),
         {:ok, line} <- integer(args, "insert_line"),
         {:ok, insert} <- string(args, "insert_text") do
      lines = String.split(text, "\n")

      if line < 0 or line > length(lines) do
        {:error,
         "Invalid insert_line #{line}: use 0 (top of the file) to #{length(lines)} " <>
           "(after the last line)."}
      else
        # One trailing newline in insert_text means "these lines", not an extra blank line.
        new = String.split(String.replace_suffix(insert, "\n", ""), "\n")
        {before, rest} = Enum.split(lines, line)
        updated = Enum.join(before ++ new ++ rest, "\n")
        {:write, Map.put(files, path, updated), "The memory file #{path} has been edited."}
      end
    end
  end

  defp delete(files, args) do
    with {:ok, path} <- path(args["path"]) do
      cond do
        path == @root ->
          {:error, "The memory directory itself cannot be deleted; delete files inside it."}

        Map.has_key?(files, path) ->
          {:write, Map.delete(files, path), "Successfully deleted #{path}"}

        dir?(files, path) ->
          {gone, kept} =
            Map.split_with(files, fn {p, _} -> String.starts_with?(p, path <> "/") end)

          {:write, kept, "Successfully deleted #{path} (#{map_size(gone)} files)"}

        true ->
          missing(path)
      end
    end
  end

  defp rename(files, args) do
    with {:ok, from} <- named_path(args, "old_path"),
         {:ok, to} <- named_path(args, "new_path") do
      cond do
        from == @root or to == @root ->
          {:error, "The memory directory itself cannot be renamed."}

        not Map.has_key?(files, from) and not dir?(files, from) ->
          missing(from)

        Map.has_key?(files, to) or dir?(files, to) ->
          {:error, "#{to} already exists; delete it first or choose another name."}

        String.starts_with?(to, from <> "/") ->
          {:error, "Cannot move #{from} inside itself."}

        parent_file(files, to) ->
          {:error, "#{parent_file(files, to)} is a file, not a directory."}

        true ->
          renamed =
            Map.new(files, fn {path, text} ->
              cond do
                path == from ->
                  {to, text}

                String.starts_with?(path, from <> "/") ->
                  {to <> String.replace_prefix(path, from, ""), text}

                true ->
                  {path, text}
              end
            end)

          if valid_files?(renamed),
            do: {:write, renamed, "Successfully renamed #{from} to #{to}"},
            else: {:error, "The new path would be too long or too deep."}
      end
    end
  end

  # ----- helpers ----------------------------------------------------------------

  defp named_path(args, key) do
    if Map.has_key?(args, key) and args[key] != nil,
      do: path(args[key]),
      else: {:error, "`#{key}` is required."}
  end

  defp dir?(_files, @root), do: true
  defp dir?(files, path), do: Enum.any?(Map.keys(files), &String.starts_with?(&1, path <> "/"))

  defp parent_file(files, path) do
    path
    |> String.split("/")
    |> Enum.drop(-1)
    |> Enum.scan(&(&2 <> "/" <> &1))
    |> Enum.find(&Map.has_key?(files, &1))
  end

  defp file(files, path) do
    case Map.fetch(files, path) do
      {:ok, text} -> {:ok, text}
      :error -> if dir?(files, path), do: {:error, "#{path} is a directory."}, else: missing(path)
    end
  end

  defp missing(path), do: {:error, "The path #{path} does not exist."}

  defp string(args, key) do
    case args[key] do
      text when is_binary(text) -> {:ok, text}
      nil -> {:error, "`#{key}` is required."}
      _ -> {:error, "`#{key}` must be a string."}
    end
  end

  defp optional_string(args, key) do
    case args[key] do
      nil -> {:ok, ""}
      text when is_binary(text) -> {:ok, text}
      _ -> {:error, "`#{key}` must be a string."}
    end
  end

  defp integer(args, key) do
    case args[key] do
      n when is_integer(n) -> {:ok, n}
      nil -> {:error, "`#{key}` is required."}
      _ -> {:error, "`#{key}` must be an integer."}
    end
  end
end

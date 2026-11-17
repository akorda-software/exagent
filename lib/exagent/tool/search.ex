defmodule ExAgent.Tool.Search do
  @moduledoc """
  Capability that hides a large tool catalogue behind a `search_tools` tool.

  Every advertised tool schema is sent with every model request. With dozens of
  MCP tools that costs many tokens per step and makes the model pick worse. With
  this capability the model first sees your regular tools plus `search_tools`;
  a search returns the best matching deferred tools by name and description, and
  those tools are offered from the next request on, for the rest of the
  conversation.

      search = ExAgent.Tool.Search.new(deferred: mcp_tools, max_results: 5)

      ExAgent.new(
        model: model,
        tools: [lookup_order | ExAgent.Tool.Search.tools(search)],
        capabilities: [search]
      )

  `tools/1` returns the `search_tools` tool followed by the deferred tools: they
  stay in the agent's inventory, so validation, permissions, approvals and
  persisted continuations treat them like any other tool. Which tools are loaded
  is derived from the `search_tools` results in the history, so it survives
  restore without extra state. Loaded tools follow the regular tools in load
  order, in this and later runs, so the tool list only changes when a search
  finds a new tool; provider prompt caches are invalidated then, not on every
  step or turn. Providers that reject any change of
  tools within a reasoning conversation are not a good fit.

  Searching ranks by keyword overlap with tool names (weighted) and
  descriptions, folding simple plurals; a query naming tools exactly returns just
  those tools. Hiding a tool is not a security boundary;
  use `ExAgent.Permissions` for authority. A loaded tool is offered even if an
  earlier capability, such as a skill gate, removed it; do not filter deferred
  tools with other capabilities. Capabilities that rewrite tool results, such as
  `ExAgent.Tool.OutputLimit`, are fine: a rewritten search result is recomputed
  from the query.

  Options for `new/1`: `:deferred` (required, tools to hide), `:max_results`
  (default `5`) and `:name` of the search tool (default `"search_tools"`).
  """

  use ExAgent.Capability

  alias ExAgent.Message.{Part, Request, Response}
  alias ExAgent.Tool

  @enforce_keys [:deferred, :names, :index, :tool]
  defstruct [:deferred, :names, :index, :tool, max_results: 5]

  @type t :: %__MODULE__{
          deferred: [Tool.t()],
          names: MapSet.t(String.t()),
          index: list(),
          tool: Tool.t(),
          max_results: pos_integer()
        }

  @doc "Build a search capability. Raises `ArgumentError` for invalid options."
  @spec new(keyword()) :: t()
  def new(opts) do
    deferred = Keyword.fetch!(opts, :deferred)
    max_results = Keyword.get(opts, :max_results, 5)
    name = Keyword.get(opts, :name, "search_tools")

    unless is_list(deferred) and deferred != [] and
             Enum.all?(deferred, &match?(%Tool{kind: :function}, &1)),
           do: raise(ArgumentError, "deferred must be a non-empty list of function tools")

    names = Enum.map(deferred, & &1.name)

    unless length(Enum.uniq(names)) == length(names) and name not in names and
             is_binary(name) and name != "",
           do: raise(ArgumentError, "deferred tool names must be unique and differ from #{name}")

    unless is_integer(max_results) and max_results in 1..50,
      do: raise(ArgumentError, "max_results must be an integer from 1 to 50")

    index = Enum.map(deferred, &{&1.name, &1.description, terms(&1.name), terms(&1.description)})

    tool =
      Tool.new(
        name: name,
        description:
          "Search #{length(deferred)} more tools by keywords or exact names. Matching " <>
            "tools become callable from your next step. Search before saying a task " <>
            "cannot be done.",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "Keywords for the capability you need, or tool names."
            }
          },
          "required" => ["query"],
          "additionalProperties" => false
        },
        takes_ctx: false,
        call: fn %{"query" => query} -> search(index, query, max_results) end
      )

    %__MODULE__{
      deferred: deferred,
      names: MapSet.new(names),
      index: index,
      tool: tool,
      max_results: max_results
    }
  end

  @doc "The search tool followed by the deferred tools, for the agent's `:tools`."
  @spec tools(t()) :: [Tool.t()]
  def tools(%__MODULE__{tool: tool, deferred: deferred}), do: [tool | deferred]

  @impl true
  def before_model_request(%__MODULE__{} = search, state) do
    offered = state.params.function_tools

    # Regular tools keep their order and loaded tools follow in load order, so a
    # new run over the same history offers the same list as the last request.
    loaded =
      for name <- loaded(search, state.messages),
          tool =
            Enum.find(offered, &(&1.name == name)) ||
              Enum.find(state.agent.tools, &(&1.name == name)),
          do: tool

    kept = Enum.reject(offered, &deferred?(search, &1))
    %{state | params: %{state.params | function_tools: kept ++ loaded}}
  end

  # Names returned by successful searches, in first-load order. A result that a
  # later capability rewrote (for example shortened to text) is recomputed from
  # the call's query; the search is a pure function of the query and catalogue.
  defp loaded(search, messages) do
    name = search.tool.name

    queries =
      for %Response{parts: parts} when is_list(parts) <- messages,
          %Part.ToolCall{tool_name: ^name} = call <- parts,
          {:ok, %{"query" => query}} when is_binary(query) <- [Part.ToolCall.args_as_map(call)],
          into: %{},
          do: {call.tool_call_id, query}

    for %Request{parts: parts} when is_list(parts) <- messages,
        %Part.ToolReturn{tool_name: ^name, status: :succeeded} = part <- parts,
        found <- found(search, part, queries),
        MapSet.member?(search.names, found),
        uniq: true,
        do: found
  end

  defp found(_search, %Part.ToolReturn{content: %{"tools" => tools}}, _queries)
       when is_list(tools),
       do: for(%{"name" => found} <- tools, do: found)

  defp found(search, %Part.ToolReturn{tool_call_id: id}, queries) do
    case Map.fetch(queries, id) do
      {:ok, query} ->
        for %{"name" => found} <- search(search.index, query, search.max_results)["tools"],
            do: found

      :error ->
        []
    end
  end

  defp deferred?(search, tool), do: MapSet.member?(search.names, tool.name)

  @doc false
  def search(index, query, max_results) when is_binary(query) do
    wanted = terms(query)
    exact = query |> String.split([",", " "], trim: true) |> MapSet.new()

    scored =
      index
      |> Enum.with_index()
      |> Enum.map(fn {{name, description, name_terms, description_terms}, position} ->
        score = 3 * overlap(wanted, name_terms) + overlap(wanted, description_terms)
        {MapSet.member?(exact, name), score, position, name, description}
      end)

    # Exact names select exactly those tools; otherwise rank by keyword overlap.
    found =
      if Enum.any?(scored, &elem(&1, 0)),
        do: Enum.filter(scored, &elem(&1, 0)),
        else:
          scored |> Enum.filter(&(elem(&1, 1) > 0)) |> Enum.sort_by(&{-elem(&1, 1), elem(&1, 2)})

    found =
      found
      |> Enum.take(max_results)
      |> Enum.map(fn {_, _, _, name, description} ->
        %{"name" => name, "description" => description || ""}
      end)

    if found == [] do
      %{
        "tools" => [],
        "message" =>
          "No tools matched. Try other keywords. Available tool names: " <>
            (index |> Enum.map(&elem(&1, 0)) |> Enum.take(200) |> Enum.join(", "))
      }
    else
      %{
        "tools" => found,
        "message" => "These tools are now available. Call them on your next step."
      }
    end
  end

  # Lower-case words, splitting snake_case, kebab-case and camelCase.
  defp terms(nil), do: MapSet.new()

  defp terms(text) do
    text
    |> String.replace(~r/([a-z0-9])([A-Z])/u, "\\1 \\2")
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 2))
    |> Enum.map(&stem/1)
    |> MapSet.new()
  end

  # Minimal plural folding, applied alike to queries and tools, so "files"
  # finds "file" and "searches" finds "search".
  defp stem(word) do
    cond do
      String.length(word) > 4 and String.ends_with?(word, "ies") ->
        String.slice(word, 0..-4//1) <> "y"

      String.length(word) > 4 and String.ends_with?(word, ["ches", "shes", "sses", "xes"]) ->
        String.slice(word, 0..-3//1)

      String.length(word) > 3 and String.ends_with?(word, "s") and
          not String.ends_with?(word, "ss") ->
        String.slice(word, 0..-2//1)

      true ->
        word
    end
  end

  defp overlap(wanted, terms), do: wanted |> MapSet.intersection(terms) |> MapSet.size()
end

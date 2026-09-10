defmodule ExAgent.Tool do
  @moduledoc """
  A tool the model may call.

  `ExAgent.Tool` bundles everything: the serialisable `ToolDefinition`
  (name, description, JSON-Schema parameters) **and** the actual callable that
  runs when the model invokes it. Use `definition/1` to project the shape a
  provider sends to the model.

  Tools are normally built via the `deftool` macro (see `ExAgent.Tools`),
  which derives the JSON-Schema from the function's `@spec`. They can also be
  built by hand with `new/1`.
  """

  @type kind :: :function | :output | :external | :unapproved

  defstruct name: nil,
            description: nil,
            parameters_json_schema: %{},
            kind: :function,
            takes_ctx: true,
            call: nil,
            max_retries: 1,
            prepared_validator: nil

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          parameters_json_schema: map() | boolean(),
          kind: kind(),
          takes_ctx: boolean(),
          call: (ExAgent.RunContext.t(), map() -> term()) | (map() -> term()) | nil,
          max_retries: non_neg_integer(),
          prepared_validator: term()
        }

  @type validation_error :: %{path: String.t(), keyword: String.t(), message: String.t()}

  @doc """
  Prepare a tool's local JSON Schema validator before requesting the model.

  The opaque `prepared_validator` field is internal, is not serialized by
  `definition/1`, and is reused only for the exact immutable schema it was built
  from. No process-global cache is used. Draft 2020-12 (default) and draft 7 are
  supported with embedded/local references; executable casts, module references,
  and fetching external schemas are not supported.

  Nested schemas must use the root dialect. The reference preflight checks
  candidate targets conservatively across embedded resources. Inert defaults
  are omitted only from the private build projection; referenced defaults are
  kept verbatim and remain subject to JSV's identifier-scanning restrictions.
  """
  @spec prepare(t()) :: {:ok, t()} | {:error, {:invalid_tool_schema, [validation_error()]}}
  def prepare(
        %__MODULE__{parameters_json_schema: schema, prepared_validator: {schema, _}} = tool
      ),
      do: {:ok, tool}

  def prepare(%__MODULE__{} = tool) do
    case ExAgent.Tool.Validator.prepare(tool.parameters_json_schema) do
      {:ok, validator} ->
        {:ok, %{tool | prepared_validator: {tool.parameters_json_schema, validator}}}

      {:error, errors} ->
        {:error, {:invalid_tool_schema, errors}}
    end
  end

  @doc """
  Validate arguments without invoking the callable or changing the original map.

  Atom and string object keys are compared as JSON strings; collisions and values
  outside the JSON data model are rejected. Values are never coerced and defaults
  are never inserted. Error paths are JSON pointers (the root is `""`).
  """
  @spec validate_args(t(), term()) :: {:ok, map()} | {:error, [validation_error()]}
  def validate_args(%__MODULE__{} = tool, args) when is_map(args) and not is_struct(args) do
    with {:ok, prepared} <- prepare(tool),
         {:ok, normal} <- ExAgent.Tool.JSON.normalize(args),
         {_, validator} = prepared.prepared_validator,
         {:ok, _} <- ExAgent.Tool.Validator.validate(normal, validator) do
      {:ok, args}
    else
      {:error, {:invalid_tool_schema, errors}} -> {:error, errors}
      {:error, _} = error -> error
    end
  end

  def validate_args(%__MODULE__{}, _),
    do: ExAgent.Tool.JSON.error("", "type", "Tool arguments must be a JSON object")

  @doc """
  Check that a successful result payload can be encoded as JSON, preserving it.

  Pass the payload after unwrapping `{:ok, payload}`. Jason-encodable structs and
  atoms are supported; duplicate JSON object keys and encoding failures reject.
  This does not impose a result schema or retry an already executed callable.
  """
  @spec validate_result(t(), term()) :: {:ok, term()} | {:error, [validation_error()]}
  def validate_result(%__MODULE__{}, result) do
    ExAgent.Tool.JSON.encoded_result(result)
  end

  @doc "Serialisable projection sent to the model: name + description + params."
  @spec definition(t()) :: map()
  def definition(%__MODULE__{} = tool) do
    %{
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters_json_schema
    }
  end

  @doc "Build a tool by hand."
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    struct!(__MODULE__, opts)
  end
end

defmodule ExAgent.Eval.Case do
  @moduledoc "One evaluation case: a name, the input and what to expect."

  defstruct [:name, :input, :expected, metadata: %{}, run_opts: []]

  @type t :: %__MODULE__{
          name: String.t(),
          input: ExAgent.prompt(),
          expected: term(),
          metadata: map(),
          run_opts: keyword()
        }

  @doc """
  Build a case. Options: `:expected` (what evaluators compare against),
  `:metadata` (any map, for custom evaluators) and `:run_opts` (merged into the
  run options for this case, for example `deps:`).
  """
  @spec new(String.t(), ExAgent.prompt(), keyword()) :: t()
  def new(name, input, opts \\ []) when is_binary(name) do
    run_opts = Keyword.get(opts, :run_opts, [])
    metadata = Keyword.get(opts, :metadata, %{})

    unless Keyword.keyword?(run_opts), do: raise(ArgumentError, "run_opts must be a keyword list")
    unless is_map(metadata), do: raise(ArgumentError, "metadata must be a map")

    %__MODULE__{
      name: name,
      input: input,
      expected: Keyword.get(opts, :expected),
      metadata: metadata,
      run_opts: run_opts
    }
  end
end

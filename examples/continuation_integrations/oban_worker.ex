defmodule ExAgent.Examples.ContinuationWorker do
  @moduledoc """
  Compile this recipe in an Oban consumer:

      use ExAgent.Examples.ContinuationWorker, host: MyApp.ContinuationHost

  `host.job_target(reference)` resolves an authorized service principal and a
  current agent/template, prompt, continuation config and run options. Job args
  contain only the opaque reference. Approval remains a separate host command.
  """
  defmacro __using__(opts) do
    host = Keyword.fetch!(opts, :host)

    quote do
      use Oban.Worker, queue: :continuations, max_attempts: 1
      @continuation_host unquote(host)

      @impl Oban.Worker
      def perform(%Oban.Job{args: args}) do
        ExAgent.Examples.ContinuationWorker.perform(@continuation_host, args)
      end
    end
  end

  def perform(host, %{"reference" => reference} = args)
      when map_size(args) == 1 and is_binary(reference) do
    with {:ok, target} <- host.job_target(reference) do
      case ExAgent.Examples.ContinuationJob.dispatch(
             target.agent,
             target.prompt,
             target.continuation,
             target.options
           ) do
        {:ok, _result} -> :ok
        {:error, _reason} -> {:cancel, :host_recovery_required}
      end
    else
      _ -> {:cancel, :unauthorized_reference}
    end
  end

  def perform(_host, _args), do: {:cancel, :invalid_reference}
end

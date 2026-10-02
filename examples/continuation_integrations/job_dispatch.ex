defmodule ExAgent.Examples.ContinuationJob do
  alias ExAgent.Continuation

  def dispatch(agent, prompt, config, options \\ []) do
    case Continuation.get(config.store, config.id) do
      {:error, :not_found} ->
        ExAgent.run(agent, prompt, Keyword.put(options, :continuation, config))

      {:ok, %{status: status, record: record}} when status in [:ready, :approved] ->
        reference = %{id: config.id, record_id: record["record_id"], revision: record["revision"]}
        ExAgent.resume(agent, reference, Keyword.put(options, :continuation, config))

      {:ok, %{status: :pending, record: record}} ->
        {:ok,
         %{
           job_action: :await_approval,
           record_id: record["record_id"],
           revision: record["revision"]
         }}

      {:ok, %{status: status, record: record}}
      when status in [:completed, :failed, :denied, :expired, :cancelled] ->
        {:ok,
         %{
           job_action: :terminal,
           status: status,
           record_id: record["record_id"],
           revision: record["revision"]
         }}

      {:ok, %{status: status}} when status in [:claimed, :executing] ->
        {:error, :attempt_in_progress}

      {:ok, %{status: :uncertain}} ->
        {:error, :host_recovery_required}

      {:error, _} = error ->
        error
    end
  end
end

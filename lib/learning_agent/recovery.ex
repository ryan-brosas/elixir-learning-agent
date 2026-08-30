defmodule LearningAgent.Recovery do
  @moduledoc """
  Startup reconciliation (docs/03 §Recovery, docs/06 Milestone 3). Runs once after
  migrations/readiness and before admission starts: finds orphaned non-terminal
  runs whose lease expired, and resets them so a fresh scheduler pass can re-claim.
  Also releases any lease still marking a vanished holder.
  """
  require Logger
  alias LearningAgent.RunContext

  def run do
    case RunContext.orphaned() do
      [] ->
        :ok

      runs ->
        Enum.each(runs, &reconcile/1)
        Logger.info("recovery_complete orphans=#{length(runs)}")
        :ok
    end
  end

  # requeue: set the run back to queued but preserve cancel-before-start; leave
  # the expired lease row (next claim increments epoch = fencing).
  defp reconcile(run) do
    if run.cancel_requested do
      RunContext.unfenced_transition(run.id, run.state, "cancelled", %{
        finished_at: DateTime.utc_now()
      })
    else
      RunContext.requeue(run)
    end
  end
end

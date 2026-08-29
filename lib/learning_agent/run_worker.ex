defmodule LearningAgent.RunWorker do
  @moduledoc """
  One repository pass worker (docs/01 §4, docs/06 Milestone 3). Temporary child of
  LearningAgent.RunSupervisor; the durable run row drives restart, so this process
  holds no authoritative state. In Milestone 3 there is no LLM: it proves the
  scheduler -> worker -> durable progress -> lease release path end-to-end and
  honors cancellation before any step. The model loop arrives in Milestone 9.
  """
  use GenServer
  require Logger
  alias LearningAgent.{RunContext, LeaseContext}

  def start_link(%LearningAgent.Run{} = run) do
    GenServer.start_link(__MODULE__, run)
  end

  @impl true
  def init(run) do
    {:ok, run, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, run) do
    case durable_pass(run) do
      {:ok, _} ->
        {:stop, :normal, run}

      {:error, reason} ->
        Logger.error("run_worker_aborted run=#{run.id} reason=#{inspect(reason)}")
        {:stop, :normal, run}
    end
  end

  # Deterministic pre-model pass (Milestone 3): verify cancel at each step,
  # advance claimed -> preflight -> note_drafting -> note_published -> exploring,
  # then release the lease. Every write is fenced on the run's lease_epoch.
  defp durable_pass(run) do
    ep = run.lease_epoch
    rid = run.id

    with {:ok, run} <- step(rid, "claimed", "preflight", ep, run),
         {:ok, run} <- step(rid, run.state, "note_drafting", ep, run),
         {:ok, run} <- step(rid, run.state, "note_published", ep, run),
         {:ok, run} <- step(rid, run.state, "exploring", ep, run) do
      release(run)
      {:ok, run}
    end
  end

  defp step(rid, from, to, ep, run) do
    if RunContext.cancelled?(get_run(run)) do
      RunContext.transition(rid, from, "cancelled", ep, %{finished_at: DateTime.utc_now()})
      {:error, :cancelled}
    else
      case RunContext.transition(rid, from, to, ep) do
        {:ok, run2} -> {:ok, run2}
        {:error, e} -> {:error, e}
      end
    end
  end

  defp get_run(run), do: RunContext.get(run.id) || run

  defp release(run) do
    # fetch a fresh lease row so epoch matches what the DB holds
    case LeaseContext.release_for(
           run.repository_id,
           run.lease_epoch,
           RunContext.holder(),
           "partial"
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("lease_release_skipped run=#{run.id} reason=#{inspect(reason)}")
    end
  end
end

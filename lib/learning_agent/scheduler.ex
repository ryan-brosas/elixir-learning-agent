defmodule LearningAgent.Scheduler do
  @moduledoc """
  Durable run admission (docs/04 §13, docs/06 Milestone 3). A timer-driven GenServer
  that selects eligible queued runs, respects a global concurrency cap, claims a
  fenced repository lease, and starts a RunWorker through RunSupervisor. SQL runs
  and leases are authoritative; the scheduler never owns the truth.
  """
  use GenServer
  require Logger
  alias LearningAgent.{RunContext, RunSupervisor}

  @tick :timer.seconds(2)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{concurrency: Keyword.get(opts, :concurrency, 100)}
    schedule()
    {:ok, state}
  end

  @doc "Manually nudge admission (used in tests)."
  def tick, do: GenServer.cast(__MODULE__, :tick)

  @impl true
  def handle_cast(:tick, state), do: {:noreply, admit(state)}

  @impl true
  def handle_info(:tick, state) do
    schedule()
    {:noreply, admit(state)}
  end

  defp schedule, do: Process.send_after(self(), :tick, @tick)

  defp admit(state) do
    headroom = max(state.concurrency - RunContext.active_count(), 0)

    if headroom > 0 do
      RunContext.eligible()
      |> Enum.take(headroom)
      |> Enum.each(&maybe_start_worker/1)
    end

    state
  end

  defp maybe_start_worker(run) do
    case RunContext.claim(run) do
      {:ok, claimed_run, _lease} ->
        case RunSupervisor.start_worker(claimed_run) do
          {:ok, _pid} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "run_worker_start_failed run=#{claimed_run.id} reason=#{inspect(reason)}"
            )
        end

      {:error, :cancelled_before_start} ->
        # preserve cancel-before-start: never start the worker.
        RunContext.unfenced_transition(run.id, "queued", "cancelled", %{
          finished_at: DateTime.utc_now()
        })

      {:error, _} ->
        # still held elsewhere (or race lost); skip this tick.
        :ok
    end
  end
end

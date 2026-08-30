defmodule LearningAgent.Scheduler do
  @moduledoc """
  Durable run admission (docs/04 §13, docs/06 Milestone 3). A timer-driven GenServer
  that selects eligible queued runs, respects a global concurrency cap, claims a
  fenced repository lease, and starts a RunWorker through RunSupervisor. SQL runs
  and leases are authoritative; the scheduler never owns the truth.
  """
  use GenServer
  require Logger

  alias LearningAgent.{
    Activity,
    LearningPass,
    Recovery,
    RepositoryContext,
    RunContext,
    RunSupervisor
  }

  @tick :timer.seconds(2)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Current admission cap. The application env is the live value; the scheduler mirrors it."
  def concurrency do
    Application.get_env(:learning_agent, :worker_slots, 1)
  end

  @doc "Raise or lower live worker slots without restart. Running passes are not killed."
  def set_concurrency(n) when is_integer(n) and n >= 1 and n <= 64 do
    Application.put_env(:learning_agent, :worker_slots, n)

    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :tick)

    {:ok, n}
  end

  def set_concurrency(_), do: {:error, :worker_slots_invalid}

  @impl true
  def init(opts) do
    concurrency =
      Keyword.get(opts, :concurrency, Application.get_env(:learning_agent, :worker_slots, 1))

    Application.put_env(:learning_agent, :worker_slots, concurrency)
    schedule()
    {:ok, %{admitting: false}}
  end

  @doc "Manually nudge admission (used in tests)."
  def tick, do: GenServer.cast(__MODULE__, :tick)

  @impl true
  def handle_cast(:tick, state), do: {:noreply, maybe_admit(state)}

  @impl true
  def handle_call({:set_concurrency, slots}, _from, state) do
    Application.put_env(:learning_agent, :worker_slots, slots)
    {:reply, {:ok, slots}, maybe_admit(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule()
    {:noreply, maybe_admit(state)}
  end

  def handle_info(:tick_done, state), do: {:noreply, %{state | admitting: false}}

  defp schedule, do: Process.send_after(self(), :tick, @tick)

  # Heavy admission work (Recovery, self-heal, claims) runs detached so the
  # loop GenServer stays responsive: every /v1/settings write and board poll
  # touches the live cap, and a call queued behind a slow tick turned into
  # HTTP 500s under worker load. The admitting flag bounds it to one tick.
  defp maybe_admit(%{admitting: true} = state), do: state

  defp maybe_admit(state) do
    parent = self()

    {:ok, _pid} =
      Task.start(fn ->
        try do
          admit(state)
        catch
          kind, reason ->
            Logger.error("scheduler_tick_failed kind=#{kind} reason=#{inspect(reason)}")
        after
          send(parent, :tick_done)
        end
      end)

    %{state | admitting: true}
  end

  defp admit(state) do
    concurrency = Application.get_env(:learning_agent, :worker_slots, 1)
    Recovery.run()
    self_heal()
    headroom = max(concurrency - RunContext.active_count(), 0)

    if headroom > 0 do
      RunContext.eligible()
      |> Enum.reduce_while(0, fn run, started ->
        if started >= headroom do
          {:halt, started}
        else
          case maybe_start_worker(run) do
            :started -> {:cont, started + 1}
            _ -> {:cont, started}
          end
        end
      end)
    end

    state
  end

  @self_heal_batch 6

  # Durable safety net: a repo stranded by a failed or lost run returns to the
  # queue without operator action. Drained repos settle to complete.
  defp self_heal do
    RunContext.stalled_repos()
    |> Enum.take(@self_heal_batch)
    |> Enum.each(fn repo ->
      cond do
        LearningPass.drained?(repo) ->
          _ = RepositoryContext.set_status(repo.id, "complete")
          Logger.info("learning_self_heal_drained repo=#{repo.slug}")

          Activity.log(
            :info,
            "self-heal: `#{repo.slug}` already squeezed; settled to complete",
            %{repo: repo.slug}
          )

        true ->
          # A finishing pass may requeue this repo concurrently; the unique
          # (repository, pass_number) index then raises. Self-heal is best-effort:
          # never let the admission loop crash over a lost race.
          try do
            case RepositoryContext.queue_pass(repo.id) do
              {:ok, run} ->
                Logger.info(
                  "learning_self_heal_requeue repo=#{repo.slug} pass=#{run.pass_number}"
                )

                Activity.log(
                  :info,
                  "self-heal: requeued `#{repo.slug}` pass #{run.pass_number}",
                  %{repo: repo.slug}
                )

              {:error, reason} ->
                Logger.warning(
                  "learning_self_heal_skipped repo=#{repo.slug} reason=#{inspect(reason)}"
                )

                Activity.log(:warn, "self-heal skipped `#{repo.slug}`: #{inspect(reason)}", %{
                  repo: repo.slug
                })
            end
          rescue
            e in Ecto.ConstraintError ->
              Logger.warning(
                "learning_self_heal_skipped repo=#{repo.slug} reason=#{String.slice(Exception.message(e), 0, 80)}"
              )

              Activity.log(
                :warn,
                "self-heal race on `#{repo.slug}` (pass number taken); skipped",
                %{repo: repo.slug}
              )
          end
      end
    end)
  end

  defp maybe_start_worker(run) do
    case RunContext.claim(run) do
      {:ok, claimed_run, _lease} ->
        case RunSupervisor.start_worker(claimed_run, LearningAgent.RuntimeSettings.take_model()) do
          {:ok, _pid} ->
            :started

          {:error, reason} ->
            Logger.error(
              "run_worker_start_failed run=#{claimed_run.id} reason=#{inspect(reason)}"
            )

            :skip
        end

      {:error, :cancelled_before_start} ->
        RunContext.unfenced_transition(run.id, "queued", "cancelled", %{
          finished_at: DateTime.utc_now()
        })

        :skip

      {:error, _} ->
        :skip
    end
  end
end

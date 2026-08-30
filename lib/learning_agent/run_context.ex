defmodule LearningAgent.RunContext do
  @moduledoc """
  Durable run operations (docs/03 §4, docs/01 §13-§15).

  Single source of truth for run lifecycle. Every protected mutation is
  epoch-fenced so a stale worker affects zero rows. Cancellation intent is durable
  and never overwritten.
  """
  import Ecto.Query
  alias LearningAgent.{Repo, Run, Lease, LeaseContext}
  alias LearningAgent.Domain.Run, as: RunDomain

  @queued "queued"
  @active [
    "claimed",
    "preflight",
    "note_drafting",
    "note_published",
    "exploring",
    "evidence_gathering",
    "synthesizing",
    "validating",
    "publishing",
    "recording_result"
  ]
  @orphan_grace_s 15
  @failure_cooldown_ms :timer.seconds(60)

  @doc "Lease TTL used for claim (ms)."
  def ttl, do: LeaseContext.ttl_ms()

  @doc "Holder identity string for this scheduler instance."
  def holder, do: "scheduler-" <> Atom.to_string(node())

  @doc "Create a queued run. (repository_id, pass_number) uniqueness blocks duplicates."
  def create(repository_id, pin_id, pass_number) do
    %Run{}
    |> Run.changeset(%{
      repository_id: repository_id,
      pin_id: pin_id,
      pass_number: pass_number,
      state: @queued
    })
    |> Repo.insert()
  end

  def get(id), do: Repo.get(Run, id)

  @doc "The in-flight run for a repository, if any. One worker holds one repo lease."
  def active_for(repository_id) do
    terminals = ["completed", "partial", "blocked", "failed", "cancelled", "orphaned"]

    from(r in Run,
      where:
        r.repository_id == ^repository_id and r.state not in ^terminals and
          r.cancel_requested == false,
      order_by: [desc: r.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Recent runs, newest first."
  def recent(limit \\ 40) when is_integer(limit) and limit in 1..200 do
    from(r in Run, order_by: [desc: r.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  @doc "Eligible queued runs (not cancelled), oldest first."
  def eligible do
    from(r in Run,
      where: r.state == ^@queued and r.cancel_requested == false,
      order_by: r.inserted_at
    )
    |> Repo.all()
  end

  @doc """
  Active repositories with nothing queued and nothing in flight — the stranded
  state after a failed or lost run. Returns full repository structs; the caller
  decides drain vs requeue. Failed runs inside `cooldown_ms` are skipped so a
  deterministic failure cannot hot-loop.
  """
  def stalled_repos(cooldown_ms \\ @failure_cooldown_ms) do
    cutoff = DateTime.add(DateTime.utc_now(), -cooldown_ms, :millisecond)

    busy = @active ++ [@queued]

    busy_repo_ids =
      from(r in Run,
        where: r.state in ^busy and r.cancel_requested == false,
        distinct: true,
        select: r.repository_id
      )
      |> Repo.all()
      |> MapSet.new()

    from(r in LearningAgent.Repository,
      where: r.status in ["registered", "active"] and is_nil(r.disabled_at)
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(busy_repo_ids, &1.id))
    |> then(fn repos ->
      case repos do
        [] ->
          []

        repos ->
          latest = latest_run_by_repo(Enum.map(repos, & &1.id))

          Enum.reject(repos, fn repo ->
            case Map.get(latest, repo.id) do
              %{state: "failed", updated_at: at} -> DateTime.compare(at, cutoff) == :gt
              _ -> false
            end
          end)
      end
    end)
  end

  defp latest_run_by_repo(ids) do
    from(r in Run,
      where: r.repository_id in ^ids,
      distinct: r.repository_id,
      order_by: [asc: r.repository_id, desc: r.updated_at, desc: r.inserted_at],
      select: %{repository_id: r.repository_id, state: r.state, updated_at: r.updated_at}
    )
    |> Repo.all()
    |> Map.new(&{&1.repository_id, &1})
  end

  @doc "Count of runs currently in-flight (admission headroom)."
  def active_count do
    states = @active
    Repo.aggregate(from(r in Run, where: r.state in ^states), :count, :id)
  end

  @doc """
  Epoch-fenced transition. Only succeeds when run is exactly in from_state and
  carries lease_epoch. A stale worker gets {:error, :stale_epoch}.
  """
  def transition(run_id, from_state, to_state, lease_epoch, attrs \\ %{}) do
    if RunDomain.valid_transition?(String.to_atom(from_state), String.to_atom(to_state)) do
      q =
        from(r in Run,
          where: r.id == ^run_id and r.state == ^from_state and r.lease_epoch == ^lease_epoch
        )

      case Repo.update_all(q, set: Map.to_list(Map.merge(%{state: to_state}, attrs))) do
        {1, _} -> {:ok, Repo.get!(Run, run_id)}
        {0, _} -> {:error, :stale_epoch}
      end
    else
      {:error, :invalid_transition}
    end
  end

  @doc "Transition without epoch fencing (operator-driven, cancel-before-start)."
  def unfenced_transition(run_id, from_state, to_state, attrs \\ %{}) do
    if RunDomain.valid_transition?(String.to_atom(from_state), String.to_atom(to_state)) do
      q = from(r in Run, where: r.id == ^run_id and r.state == ^from_state)

      case Repo.update_all(q, set: Map.to_list(Map.put(attrs, :state, to_state))) do
        {1, _} -> {:ok, Repo.get!(Run, run_id)}
        {0, _} -> {:error, :wrong_state}
      end
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Claim a queued run under a fenced lease. lease.repository_id is the lease PK, so a
  live lease blocks re-claim; an expired lease is reclaimed with epoch+1 (fencing).
  Then the run's state -> claimed and its lease_epoch column records the held epoch.
  """
  def claim(run) do
    with {:ok, lease} <- LeaseContext.claim(run.repository_id, run.id, holder()) do
      q =
        from(r in Run,
          where: r.id == ^run.id and r.state == "queued" and r.cancel_requested == false
        )

      case Repo.update_all(q, set: [state: "claimed", lease_epoch: lease.epoch]) do
        {1, _} -> {:ok, Repo.get!(Run, run.id), lease}
        {0, _} -> {:error, :cancelled_before_start}
      end
    end
  end

  @doc "Durable cancellation intent; never flips true -> false."
  def request_cancel(run_id) do
    run = Repo.get!(Run, run_id)

    if run.cancel_requested do
      {:ok, run}
    else
      run
      |> Ecto.Changeset.change(cancel_requested: true, cancel_requested_at: DateTime.utc_now())
      |> Repo.update()
    end
  end

  @doc "Requeue failed IO/permission runs after the skills root becomes writable."
  def retry_failed_io do
    from(r in Run,
      where:
        r.state == "failed" and
          (is_nil(r.failure_class) or r.failure_class in ["not_writable", "eacces"])
    )
    |> Repo.all()
    |> Enum.reduce(0, fn run, n ->
      case requeue(run) do
        {:ok, _} -> n + 1
        _ -> n
      end
    end)
  end

  def requeue(run) do
    now = DateTime.utc_now()
    q = from(r in Run, where: r.id == ^run.id)

    case Repo.update_all(q, set: [state: "queued", lease_epoch: nil]) do
      {1, _} ->
        from(l in Lease, where: l.repository_id == ^run.repository_id)
        |> Repo.update_all(
          set: [
            released_at: now,
            release_outcome: "orphaned",
            expires_at: DateTime.add(now, -1, :second)
          ]
        )

        {:ok, Repo.get!(Run, run.id)}

      {0, _} ->
        {:error, :not_found}
    end
  end

  @doc "Whether the durable run row has cancellation intent set."
  def cancelled?(%Run{cancel_requested: true}), do: true
  def cancelled?(_), do: false

  @doc "Runs stuck non-terminal whose lease has expired or been released (worker vanished)."
  def orphaned do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@orphan_grace_s, :second)
    states = @active

    lease_orphans =
      from(r in Run,
        join: l in Lease,
        on: l.repository_id == r.repository_id,
        where:
          r.state in ^states and
            (not is_nil(l.released_at) or l.expires_at < ^now),
        select: r
      )
      |> Repo.all()

    process_orphans =
      from(r in Run, where: r.state in ^states and r.updated_at < ^cutoff)
      |> Repo.all()
      |> Enum.filter(fn run -> not worker_alive?(run.id) end)

    Enum.uniq_by(lease_orphans ++ process_orphans, & &1.id)
  end

  defp worker_alive?(run_id) do
    case Registry.lookup(LearningAgent.Registry, run_id) do
      [{pid, _}] -> Process.alive?(pid)
      _ -> false
    end
  end
end

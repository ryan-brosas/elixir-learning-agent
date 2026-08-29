defmodule LearningAgent.RunContext do
  @moduledoc """
  Durable run operations (docs/03 §4, docs/01 §13-§15).

  Single source of truth for run lifecycle. Every protected mutation is
  epoch-fenced so a stale worker affects zero rows. Cancellation intent is durable
  and never overwritten.
  """
  import Ecto.Query
  alias LearningAgent.{Repo, Run, Lease}
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
  @lease_ttl :timer.minutes(5)

  @doc "Lease TTL used for claim (ms)."
  def ttl, do: @lease_ttl

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

  @doc "Eligible queued runs (not cancelled), oldest first."
  def eligible do
    from(r in Run,
      where: r.state == ^@queued and r.cancel_requested == false,
      order_by: r.inserted_at
    )
    |> Repo.all()
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
    now = DateTime.utc_now()
    expiry = DateTime.add(now, @lease_ttl)

    with {:ok, lease} <- acquire_lease(run, now, expiry) do
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

  defp acquire_lease(run, now, expiry) do
    case Repo.get(Lease, run.repository_id) do
      nil ->
        %Lease{
          repository_id: run.repository_id,
          run_id: run.id,
          holder_id: holder(),
          epoch: 1,
          claimed_at: now,
          renewed_at: now,
          expires_at: expiry
        }
        |> Repo.insert()

      l ->
        if DateTime.compare(l.expires_at, now) == :lt do
          reclaim(l, run, now, expiry)
        else
          {:error, :still_held}
        end
    end
  end

  defp reclaim(l, run, now, expiry) do
    l
    |> Ecto.Changeset.change(
      run_id: run.id,
      holder_id: holder(),
      epoch: l.epoch + 1,
      claimed_at: now,
      renewed_at: now,
      expires_at: expiry,
      released_at: nil,
      release_outcome: nil
    )
    |> Repo.update()
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

  @doc """
  Recovery reset: move an orphaned non-terminal run back to queued and clear its
  fencing epoch so a fresh claim may own it. This is a recovery-only path, not a
  normal state-machine transition; applied only to runs whose worker/lease vanished.
  """
  def requeue(run) do
    q = from(r in Run, where: r.id == ^run.id)

    case Repo.update_all(q, set: [state: "queued", lease_epoch: nil]) do
      {1, _} -> {:ok, Repo.get!(Run, run.id)}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc "Whether the durable run row has cancellation intent set."
  def cancelled?(%Run{cancel_requested: true}), do: true
  def cancelled?(_), do: false

  @doc "Runs stuck non-terminal whose lease has expired or been released (worker vanished)."
  def orphaned do
    now = DateTime.utc_now()
    states = @active

    from(r in Run,
      join: l in Lease,
      on: l.repository_id == r.repository_id,
      where:
        r.state in ^states and
          is_nil(l.released_at) and l.expires_at < ^now,
      select: r
    )
    |> Repo.all()
  end
end

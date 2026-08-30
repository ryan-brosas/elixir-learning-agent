defmodule LearningAgent.LeaseContext do
  @moduledoc """
  Fenced lease operations (docs/01 §15, docs/05 §7).

  leases.repository_id is the primary key, so a hold is exclusive per repository.
  Claim is an upsert that increments epoch (fencing) when the previous lease is
  expired or released; every protected mutation elsewhere must gate on the current
  epoch so a stale worker updates zero rows.
  """
  import Ecto.Changeset
  alias LearningAgent.{Repo, Lease}

  @lease_ttl_ms :timer.minutes(5)

  def ttl_ms, do: @lease_ttl_ms

  def expires_at(now \\ DateTime.utc_now()) do
    DateTime.add(now, @lease_ttl_ms, :millisecond)
  end

  def claim(repository_id, run_id, holder_id) do
    now = DateTime.utc_now()
    expires = expires_at(now)

    case Repo.get(Lease, repository_id) do
      nil ->
        Repo.insert(%Lease{
          repository_id: repository_id,
          run_id: run_id,
          holder_id: holder_id,
          epoch: 1,
          claimed_at: now,
          renewed_at: now,
          expires_at: expires,
          released_at: nil
        })

      lease ->
        if reclaimable?(lease, now) do
          lease
          |> cast(
            %{
              run_id: run_id,
              holder_id: holder_id,
              epoch: lease.epoch + 1,
              claimed_at: now,
              renewed_at: now,
              expires_at: expires,
              released_at: nil,
              release_outcome: nil
            },
            [
              :run_id,
              :holder_id,
              :epoch,
              :claimed_at,
              :renewed_at,
              :expires_at,
              :released_at,
              :release_outcome
            ]
          )
          |> validate_required([:run_id, :holder_id])
          |> Repo.update()
        else
          {:error, :still_held}
        end
    end
  end

  def renew(lease, epoch, holder_id) when lease.epoch == epoch and lease.holder_id == holder_id do
    lease
    |> change(renewed_at: DateTime.utc_now(), expires_at: expires_at())
    |> Repo.update()
  end

  def renew(_, _, _), do: {:error, :stale_epoch}

  def release(lease, epoch, holder_id, outcome) do
    if lease.epoch == epoch and lease.holder_id == holder_id do
      lease
      |> change(released_at: DateTime.utc_now(), release_outcome: outcome)
      |> Repo.update()
    else
      {:error, :stale_epoch}
    end
  end

  @doc "Release by (repository_id, epoch, holder): stale holder/epoch is rejected (fencing)."
  def release_for(repository_id, epoch, holder_id, outcome) do
    case Repo.get(Lease, repository_id) do
      nil ->
        {:error, :no_lease}

      lease ->
        release(lease, epoch, holder_id, outcome)
    end
  end

  @doc "Fetch the current live lease for a repository."
  def current(repository_id), do: Repo.get(Lease, repository_id)

  def reclaimable?(%Lease{} = lease, now \\ DateTime.utc_now()) do
    not is_nil(lease.released_at) or DateTime.compare(lease.expires_at, now) == :lt
  end
end

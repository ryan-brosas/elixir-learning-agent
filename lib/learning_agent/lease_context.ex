defmodule LearningAgent.LeaseContext do
  @moduledoc """
  Fenced lease operations (docs/01 §15, docs/05 §7).

  leases.repository_id is the primary key, so a hold is exclusive per repository.
  Claim is an upsert that increments epoch (fencing) when the previous lease is
  expired; every protected mutation elsewhere must gate on the current epoch so a
  stale worker updates zero rows.
  """
  import Ecto.Changeset
  alias LearningAgent.{Repo, Lease}

  @lease_ttl :timer.minutes(5)

  def claim(repository_id, run_id, holder_id) do
    now = DateTime.utc_now()
    expires = DateTime.add(now, @lease_ttl)

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
        if expired?(lease) do
          lease
          |> cast(
            %{
              run_id: run_id,
              holder_id: holder_id,
              epoch: lease.epoch + 1,
              claimed_at: now,
              renewed_at: now,
              expires_at: expires,
              released_at: nil
            },
            [:run_id, :holder_id, :epoch, :claimed_at, :renewed_at, :expires_at, :released_at]
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
    |> change(
      renewed_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), @lease_ttl)
    )
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
        if lease.epoch == epoch and lease.holder_id == holder_id do
          lease
          |> change(released_at: DateTime.utc_now(), release_outcome: outcome)
          |> Repo.update()
        else
          {:error, :stale_epoch}
        end
    end
  end

  @doc "Fetch the current live lease for a repository."
  def current(repository_id), do: Repo.get(Lease, repository_id)

  defp expired?(lease) do
    DateTime.compare(lease.expires_at, DateTime.utc_now()) == :lt
  end
end

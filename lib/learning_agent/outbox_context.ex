defmodule LearningAgent.OutboxContext do
  @moduledoc """
  Outbox operations (docs/03 §16-§20). The unique idempotency_key makes a
  duplicate insert fail, so at-most-once append is DB-enforced even across
  retries. Contents are addressed by distinct content digests.
  """
  import Ecto.Query
  alias LearningAgent.{Repo, OutboxEvent}

  @doc "Insert an outbox event. Duplicate idempotency_key => {:error, :duplicate_key}."
  def append(attrs) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Count pending+retry events (backlog)."
  def backlog do
    Repo.aggregate(
      from(e in OutboxEvent, where: e.state in ["pending", "retry_wait"]),
      :count,
      :id
    )
  end

  @doc "Claim eligible pending events (oldest first), up to :limit."
  def claim_pending(limit \\ 10, holder \\ "publisher-1") do
    now = DateTime.utc_now()

    pending =
      from(e in OutboxEvent, where: e.state == "pending", order_by: e.inserted_at, limit: ^limit)
      |> Repo.all()

    Enum.map(pending, fn e ->
      {:ok, _} =
        e
        |> Ecto.Changeset.change(
          state: "claimed",
          held_by: holder,
          claimed_at: now,
          attempt_count: e.attempt_count + 1
        )
        |> Repo.update()

      Repo.get!(OutboxEvent, e.id)
    end)
  end

  @doc "Mark delivered (idempotent by key)."
  def deliver(event, remote_ref) do
    event
    |> Ecto.Changeset.change(
      state: "delivered",
      delivered_at: DateTime.utc_now(),
      payload: Map.put(event.payload || %{}, "remote_ref", remote_ref)
    )
    |> Repo.update()
  end

  @doc "Mark a transient failure for retry."
  def retry(event, reason) do
    state = if event.attempt_count >= 3, do: "failed", else: "retry_wait"

    event
    |> Ecto.Changeset.change(
      state: state,
      payload: Map.put(event.payload || %{}, "last_error", inspect(reason))
    )
    |> Repo.update()
  end

  @doc """
  Reset stale claims and overdue retry_wait events to pending. A publisher that
  dies mid-drain strands claimed rows no live process will ever release, and
  retry_wait has no scheduler of its own; without a reclaim ladder both states
  strand events forever. Returns the number of reclaimed events.
  """
  def reclaim_stale(cutoff) do
    {claimed, _} =
      from(e in OutboxEvent,
        where: e.state == "claimed" and e.claimed_at < ^cutoff
      )
      |> Repo.update_all(set: [state: "pending", held_by: nil, claimed_at: nil])

    {waited, _} =
      from(e in OutboxEvent,
        where: e.state == "retry_wait" and e.updated_at < ^cutoff
      )
      |> Repo.update_all(set: [state: "pending", held_by: nil, claimed_at: nil])

    claimed + waited
  end

  @doc "Operator retry: reset a failed/retry event to pending for a fresh claim."
  def retry!(id) do
    case Repo.get(OutboxEvent, id) do
      nil ->
        {:error, :not_found}

      event ->
        {:ok, _} =
          event
          |> Ecto.Changeset.change(state: "pending", held_by: nil, claimed_at: nil)
          |> Repo.update()

        {:ok, event}
    end
  end

  @doc "Mark a permanent failure."
  def fail(event, reason) do
    event
    |> Ecto.Changeset.change(
      state: "failed",
      payload: Map.put(event.payload || %{}, "last_error", inspect(reason))
    )
    |> Repo.update()
  end
end

defmodule LearningAgent.OutboxEvent do
  @moduledoc """
  Durable OpenViking outbox intent (docs/03 §16-§17, §20).

  The idempotency_key is unique, so a duplicate insert is rejected by the
  database, giving exactly-once delivery intent regardless of retries.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "outbox_events" do
    field(:repository_id, :binary_id)
    field(:run_id, :binary_id)
    field(:idempotency_key, :string)
    field(:event_type, :string)
    field(:destination, :string)
    field(:payload, :map, default: %{})
    field(:state, :string, default: "pending")
    field(:attempt_count, :integer, default: 0)
    field(:held_by, :string)
    field(:claimed_at, :utc_datetime_usec)
    field(:delivered_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :repository_id,
      :run_id,
      :idempotency_key,
      :event_type,
      :destination,
      :payload
    ])
    |> validate_required([:repository_id, :idempotency_key, :event_type])
    |> unique_constraint(:idempotency_key, name: "outbox_events_idempotency_key_index")
  end
end

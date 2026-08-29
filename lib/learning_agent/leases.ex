defmodule LearningAgent.Lease do
  @moduledoc """
  Fenced repository lease (docs/01 §15, docs/02 §14).

  The repository_id is the primary key, so at most one current lease exists per
  repository. Claiming increments epoch; every protected write must carry the
  current epoch (Compare-and-swap), so a stale holder updates zero rows.
  """
  use Ecto.Schema

  @primary_key false

  schema "leases" do
    field(:repository_id, :binary_id, primary_key: true)
    field(:run_id, :binary_id)
    field(:holder_id, :string)
    field(:epoch, :integer)
    field(:claimed_at, :utc_datetime_usec)
    field(:renewed_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:released_at, :utc_datetime_usec)
    field(:release_outcome, :string)
  end
end

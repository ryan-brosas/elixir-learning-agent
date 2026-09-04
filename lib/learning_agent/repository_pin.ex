defmodule LearningAgent.RepositoryPin do
  @moduledoc """
  Immutable source/graph identity observation for a repository (docs/03 §4).
  Uniquely pinned by (repository_id, root, branch, commit_sha, graph_generation)
  so duplicate pin observations are rejected.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "repository_pins" do
    field(:repository_id, :binary_id)
    field(:root, :string)
    field(:branch, :string)
    field(:commit_sha, :string)
    field(:graph_generation, :string)
    field(:observed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(pin, attrs) do
    observed = Map.get(attrs, :observed_at, DateTime.utc_now())

    pin
    |> cast(Map.put(attrs, :observed_at, observed), [
      :repository_id,
      :root,
      :branch,
      :commit_sha,
      :graph_generation,
      :observed_at
    ])
    |> validate_required([:repository_id, :root])
    |> unique_constraint(:repository_id, name: :repository_pins_identity_index)
  end
end

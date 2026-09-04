defmodule LearningAgent.Repository do
  @moduledoc """
  Registered source repository (docs/03 §4).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "repositories" do
    field(:slug, :string)
    field(:display_name, :string)
    field(:source_locator, :string)
    field(:canonical_root, :string)
    field(:graph_project, :string)
    field(:status, :string, default: "registered")
    field(:next_pass_number, :integer, default: 1)
    field(:disabled_at, :utc_datetime_usec)
    field(:active_pin_id, :binary_id)
    field(:active_generation_id, :binary_id)
    timestamps(type: :utc_datetime_usec)

    has_many(:pins, LearningAgent.RepositoryPin)
  end

  @required ~w(slug display_name source_locator graph_project)a

  def changeset(repo, attrs) do
    repo
    |> cast(
      attrs,
      @required ++
        [
          :canonical_root,
          :status,
          :next_pass_number,
          :disabled_at,
          :active_pin_id,
          :active_generation_id
        ]
    )
    |> validate_required(@required)
    |> unique_constraint(:slug, name: :repositories_slug_index)
  end

  @valid_statuses [
    "registered",
    "index_unknown",
    "index_ready",
    "active",
    "complete",
    "blocked",
    "stale",
    "disabled"
  ]

  def update_status(repo, status) do
    repo
    |> change(status: status)
    |> validate_inclusion(:status, @valid_statuses)
  end
end

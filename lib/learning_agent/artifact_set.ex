defmodule LearningAgent.ArtifactSet do
  @moduledoc """
  Persisted identity and activation state of one complete foundation projection.

  `learning_note_id` is the existing causal work-record link; the projection's
  semantic inputs are the accepted capsules selected by `repository_id` + `pin_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "artifact_sets" do
    field(:run_id, :binary_id)
    field(:learning_note_id, :binary_id)
    field(:repository_id, :binary_id)
    field(:pin_id, :binary_id)
    field(:generation, :integer)
    field(:manifest_digest, :string)
    field(:state, :string, default: "staged")
    field(:staging_path, :string)
    field(:active_path, :string)
    field(:producer, :string)
    field(:projection_version, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(run_id learning_note_id repository_id pin_id generation manifest_digest state producer projection_version)a

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, @required ++ [:staging_path, :active_path])
    |> validate_required(@required)
    |> validate_inclusion(:state, ["staged", "active", "conflict"])
  end
end

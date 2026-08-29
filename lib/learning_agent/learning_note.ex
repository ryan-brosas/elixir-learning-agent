defmodule LearningAgent.LearningNote do
  @moduledoc """
  Durable note-first work record (docs/01 §13, docs/03 §4).

  One note per run (unique on run_id). Published status requires file_path and
  file_digest so an artifact can never reference a note that isn't materialized.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "learning_notes" do
    field(:run_id, :binary_id)
    field(:repository_id, :binary_id)
    field(:content, :string)
    field(:content_digest, :string)
    field(:status, :string, default: "draft")
    field(:file_path, :string)
    field(:file_digest, :string)
    field(:committed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(run_id repository_id content content_digest)a

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :run_id,
      :repository_id,
      :content,
      :content_digest,
      :status,
      :file_path,
      :file_digest,
      :committed_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:status, ["draft", "published"])
    |> unique_constraint(:run_id, name: "learning_notes_run_id_index")
  end
end

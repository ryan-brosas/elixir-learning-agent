defmodule LearningAgent.FoundationCapsule do
  @moduledoc """
  Immutable accepted seam capsule backed by direct evidence at one repository pin.

  `stable_key` is derived from the seam boundary, never from a pass number.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "foundation_capsules" do
    field(:repository_id, :binary_id)
    field(:pin_id, :binary_id)
    field(:observation_id, :binary_id)
    field(:stable_key, :string)
    field(:source_path, :string)
    field(:source_excerpt, :string)
    field(:source_digest, :string)
    field(:source_revision, :string)
    field(:test_evidence, :string)
    field(:test_caveat, :string)
    field(:question, :string)
    field(:boundary, :string)
    field(:invariant, :string)
    field(:limits, :string)
    field(:status, :string, default: "accepted")
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @required ~w(repository_id pin_id observation_id stable_key source_path source_excerpt source_digest source_revision question boundary invariant limits status)a

  def changeset(capsule, attrs) do
    capsule
    |> cast(attrs, @required ++ [:test_evidence, :test_caveat])
    |> validate_required(@required)
    |> validate_inclusion(:status, ["accepted"])
    |> validate_source_digest()
    |> validate_test_binding()
    |> unique_constraint([:repository_id, :pin_id, :stable_key],
      name: :foundation_capsules_repository_id_pin_id_stable_key_index
    )
  end

  defp validate_source_digest(changeset) do
    excerpt = get_field(changeset, :source_excerpt)
    recorded = get_field(changeset, :source_digest)

    expected =
      if is_binary(excerpt),
        do: :crypto.hash(:sha256, excerpt) |> Base.encode16(case: :lower),
        else: nil

    if is_binary(recorded) and recorded == expected,
      do: changeset,
      else: add_error(changeset, :source_digest, "must match the direct source excerpt")
  end

  defp validate_test_binding(changeset) do
    evidence = get_field(changeset, :test_evidence)
    caveat = get_field(changeset, :test_caveat)

    if present?(evidence) or present?(caveat) do
      changeset
    else
      add_error(changeset, :test_caveat, "test evidence or an explicit caveat is required")
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

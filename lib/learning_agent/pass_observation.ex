defmodule LearningAgent.PassObservation do
  @moduledoc """
  Immutable, pin-scoped record of one learning pass.

  It stores only bounded source observations and projection context. The context
  exposes insert/idempotent replay, never update. Published notes are causal work
  records and are deliberately not the memory input of later passes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pass_observations" do
    field(:repository_id, :binary_id)
    field(:run_id, :binary_id)
    field(:pin_id, :binary_id)
    field(:pass_number, :integer)
    field(:source_paths, {:array, :string}, default: [])
    field(:direct_evidence, :map, default: %{})
    field(:model, :string)
    field(:coverage, :map, default: %{})
    field(:unresolved, {:array, :string}, default: [])
    field(:omissions, {:array, :string}, default: [])
    field(:observed_at, :utc_datetime_usec)
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @required ~w(repository_id run_id pin_id pass_number source_paths direct_evidence coverage unresolved omissions observed_at)a

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, @required ++ [:model])
    |> validate_required(@required)
    |> unique_constraint(:run_id, name: :pass_observations_run_id_index)
  end
end

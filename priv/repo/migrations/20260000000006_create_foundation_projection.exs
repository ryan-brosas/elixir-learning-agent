defmodule LearningAgent.Repo.Migrations.CreateFoundationProjection do
  use Ecto.Migration

  def change do
    create table(:pass_observations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :pin_id, references(:repository_pins, type: :uuid, on_delete: :delete_all), null: false
      add :pass_number, :integer, null: false
      add :source_paths, {:array, :string}, null: false, default: []
      add :direct_evidence, :map, null: false, default: %{}
      add :model, :string
      add :coverage, :map, null: false, default: %{}
      add :unresolved, {:array, :string}, null: false, default: []
      add :omissions, {:array, :string}, null: false, default: []
      add :observed_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:pass_observations, [:run_id])
    create index(:pass_observations, [:repository_id, :pin_id, :pass_number])

    create table(:foundation_capsules, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :pin_id, references(:repository_pins, type: :uuid, on_delete: :delete_all), null: false
      add :observation_id, references(:pass_observations, type: :uuid, on_delete: :restrict), null: false
      add :stable_key, :string, null: false
      add :source_path, :string, null: false
      add :source_excerpt, :text, null: false
      add :source_digest, :string, null: false
      add :source_revision, :string, null: false
      add :test_evidence, :text
      add :test_caveat, :text
      add :question, :text, null: false
      add :boundary, :text, null: false
      add :invariant, :text, null: false
      add :limits, :text, null: false
      add :status, :string, null: false, default: "accepted"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:foundation_capsules, [:repository_id, :pin_id, :stable_key])
    create index(:foundation_capsules, [:repository_id, :pin_id, :status])

    alter table(:artifact_sets) do
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all)
      add :pin_id, references(:repository_pins, type: :uuid, on_delete: :delete_all)
      add :producer, :string
      add :projection_version, :integer
    end

    create index(:artifact_sets, [:repository_id, :pin_id, :state])
  end
end

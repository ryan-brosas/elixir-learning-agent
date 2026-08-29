defmodule LearningAgent.Repo.Migrations.CreateArtifactsAndOutbox do
  use Ecto.Migration

  def change do
    create table(:artifact_sets, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :learning_note_id, references(:learning_notes, type: :uuid), null: false
      add :generation, :integer, null: false
      add :manifest_digest, :string
      add :state, :string, null: false, default: "staged"
      add :staging_path, :string
      add :active_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:outbox_events, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all)
      add :idempotency_key, :string, null: false
      add :event_type, :string, null: false
      add :destination, :string
      add :payload, :map, default: %{}
      add :state, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :held_by, :string
      add :claimed_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:outbox_events, [:idempotency_key])
    create index(:outbox_events, [:state, :repository_id])

    # repository_pins and artifact_sets now exist; add the active link columns.
    alter table(:repositories) do
      add :active_pin_id, references(:repository_pins, type: :uuid, on_delete: :nilify_all)
      add :active_generation_id, references(:artifact_sets, type: :uuid, on_delete: :nilify_all)
    end
  end
end

defmodule LearningAgent.Repo.Migrations.CreateRunsAndTransitions do
  use Ecto.Migration

  def change do
    create table(:runs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :pin_id, references(:repository_pins, type: :uuid, on_delete: :delete_all), null: false
      add :pass_number, :integer, null: false
      add :state, :string, null: false, default: "queued"
      add :outcome, :string
      add :lease_epoch, :bigint
      add :current_gate, :string
      add :selected_subsystem_id, :uuid
      add :learning_note_id, :uuid
      add :artifact_set_id, :uuid
      add :cancel_requested, :boolean, null: false, default: false
      add :cancel_requested_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :blocked_reason, :string
      add :failure_class, :string
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:runs, [:repository_id, :pass_number])

    create table(:run_transitions, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :from_state, :string
      add :to_state, :string, null: false
      add :event, :string, null: false
      add :lease_epoch, :bigint
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end
    create index(:run_transitions, [:run_id])
  end
end

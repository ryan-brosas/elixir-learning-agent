defmodule LearningAgent.Repo.Migrations.CreateLeasesGatesNotes do
  use Ecto.Migration

  def change do
    # One row per repository: the live fenced lease. Row lock / epoch give fencing.
    create table(:leases, primary_key: false) do
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false, primary_key: true
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :holder_id, :string, null: false
      add :epoch, :bigint, null: false, default: 1
      add :claimed_at, :utc_datetime_usec, null: false
      add :renewed_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec
      add :release_outcome, :string
    end
    create index(:leases, [:run_id])
    create unique_index(:leases, [:repository_id])

    # Seven gates per run that gate progression.
    create table(:gates, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :state, :string, null: false, default: "pending"
      add :attempt, :integer, null: false, default: 0
      add :summary, :string
      add :input_digest, :string
      add :result_digest, :string
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:gates, [:run_id, :name, :attempt])

    # Note-first: one committed note per run, created before any artifact.
    create table(:learning_notes, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :content_digest, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :committed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:learning_notes, [:run_id])
  end
end

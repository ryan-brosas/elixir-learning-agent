defmodule LearningAgent.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    create table(:repositories, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :slug, :string, null: false
      add :display_name, :string, null: false
      add :source_locator, :string, null: false
      add :canonical_root, :string
      add :graph_project, :string, null: false
      add :status, :string, null: false, default: "registered"
      add :next_pass_number, :integer, null: false, default: 1
      add :disabled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:repositories, [:slug])
    create index(:repositories, [:status])

    create table(:repository_pins, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :root, :string, null: false
      add :branch, :string
      add :commit_sha, :string
      add :graph_generation, :string
      add :observed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:repository_pins, [:repository_id, :root, :branch, :commit_sha])
  end
end

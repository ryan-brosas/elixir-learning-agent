defmodule LearningAgent.Repo.Migrations.CreateInventoryAndEvidence do
  use Ecto.Migration

  def change do
    create table(:inventory_items, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :pin_id, references(:repository_pins, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :stable_key, :string, null: false
      add :display_name, :string, null: false
      add :source_path, :string
      add :source_symbol, :string
      add :discovery_state, :string, null: false, default: "unknown"
      add :adjudication_state, :string
      add :reason_code, :string
      add :parent_id, :uuid
      add :created_by_evidence_id, :uuid
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:inventory_items, [:repository_id, :pin_id, :stable_key])

    create table(:claims, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :seam_id, references(:inventory_items, type: :uuid, on_delete: :delete_all), null: false
      add :statement, :text, null: false
      add :boundary, :text
      add :authority_state, :string
      add :source_path, :string
      add :source_symbol, :string
      add :start_line, :integer
      add :end_line, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create table(:evidence, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:runs, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :authority_class, :string, null: false
      add :operation, :string, null: false
      add :arguments, :map, default: %{}
      add :response_digest, :string
      add :body, :text
      add :pin_id, references(:repository_pins, type: :uuid)
      timestamps(type: :utc_datetime_usec)
    end
    create index(:evidence, [:run_id, :authority_class])
  end
end

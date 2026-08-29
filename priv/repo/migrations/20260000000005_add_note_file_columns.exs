defmodule LearningAgent.Repo.Migrations.AddNoteFileColumns do
  use Ecto.Migration

  def change do
    alter table(:learning_notes) do
      add :file_path, :string
      add :file_digest, :string
    end

    create index(:learning_notes, [:status])
  end
end
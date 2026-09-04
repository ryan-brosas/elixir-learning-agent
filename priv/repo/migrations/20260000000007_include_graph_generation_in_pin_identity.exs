defmodule LearningAgent.Repo.Migrations.IncludeGraphGenerationInPinIdentity do
  use Ecto.Migration

  def up do
    drop unique_index(:repository_pins, [:repository_id, :root, :branch, :commit_sha])

    execute """
    CREATE UNIQUE INDEX repository_pins_identity_index
    ON repository_pins (
      repository_id,
      root,
      COALESCE(branch, ''),
      COALESCE(commit_sha, ''),
      COALESCE(graph_generation, '')
    )
    """
  end

  def down do
    execute "DROP INDEX repository_pins_identity_index"
    create unique_index(:repository_pins, [:repository_id, :root, :branch, :commit_sha])
  end
end

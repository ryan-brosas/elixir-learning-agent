defmodule Mix.Tasks.LearningAgent.Migrate do
  @moduledoc "Run database migrations via the release."
  use Mix.Task

  @shortdoc "Run the app migrations"
  def run(_args) do
    Mix.Task.run("app.start")

    Ecto.Migrator.run(
      LearningAgent.Repo,
      Application.app_dir(:learning_agent, "priv/repo/migrations"),
      :up,
      all: true
    )
  end
end

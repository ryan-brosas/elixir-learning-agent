defmodule LearningAgent.Repo do
  use Ecto.Repo,
    otp_app: :learning_agent,
    adapter: Ecto.Adapters.Postgres
end

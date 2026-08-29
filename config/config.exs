import Config

config :learning_agent,
  ecto_repos: [LearningAgent.Repo],
  http_port: String.to_integer(System.get_env("LA_HTTP_PORT", "4000"))

config :learning_agent, LearningAgent.Repo,
  username: System.get_env("LA_DB_USER", "learning_agent"),
  password: System.get_env("LA_DB_PASS", "learning_agent"),
  hostname: System.get_env("LA_DB_HOST", "127.0.0.1"),
  database: System.get_env("LA_DB_NAME", "learning_agent_dev"),
  port: String.to_integer(System.get_env("LA_DB_PORT", "5433")),
  pool_size: String.to_integer(System.get_env("LA_POOL_SIZE", "10")),
  show_sensitive_data_on_connection_error: true

if config_env() == :test do
  config :learning_agent, http_port: nil

  config :learning_agent, LearningAgent.Repo,
    database: "learning_agent_test",
    pool: Ecto.Adapters.SQL.Sandbox

  # The scheduler/renewer are OTP loops that own the DB from their own processes;
  # in tests they would fight the per-test sandbox, so they are started explicitly
  # by tests that need them, not by the auto-started application.
  config :learning_agent, scheduler: :disabled, lease_renewer: :disabled
end

import Config

import Config

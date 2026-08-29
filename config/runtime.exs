import Config

# Release-time configuration (docs/04 §config). Loaded by `mix release` runtime.
if config_env() == :prod do
  config :learning_agent, LearningAgent.Repo,
    username: System.get_env("LA_DB_USER", "learning_agent"),
    password: System.get_env("LA_DB_PASS", "learning_agent"),
    hostname: System.get_env("LA_DB_HOST", "postgres"),
    database: System.get_env("LA_DB_NAME", "learning_agent"),
    port: String.to_integer(System.get_env("LA_DB_PORT", "5432")),
    pool_size: String.to_integer(System.get_env("LA_POOL_SIZE", "10"))
end

import Config

config :learning_agent,
  ecto_repos: [LearningAgent.Repo],
  http_port: String.to_integer(System.get_env("LA_HTTP_PORT", "4000")),
  skills_root: System.get_env("LA_SKILLS_ROOT", ".agents/skills"),
  source_root: System.get_env("LA_SOURCE_ROOT", "sources"),
  max_auto_passes: 0,
  model_retry_limit:
    (case Integer.parse(System.get_env("LA_MODEL_RETRY_LIMIT", "100")) do
       {n, ""} when n in 1..100 -> n
       _ -> 100
     end),
  model_retry_sleep: true,
  worker_slots:
    (case Integer.parse(System.get_env("LA_WORKER_SLOTS", "1")) do
       {n, ""} when n in 1..64 -> n
       _ -> 1
     end),
  settings_path: Path.expand("data/runtime-settings.json"),
  local_dogfood: true,
  model: [
    adapter: :openai_compatible,
    base_url: nil,
    model: nil,
    api_key: nil,
    timeout_ms: 15_000
  ]

config :learning_agent, LearningAgent.Repo,
  username: System.get_env("LA_DB_USER", "learning_agent"),
  password: System.get_env("LA_DB_PASS", "learning_agent"),
  hostname: System.get_env("LA_DB_HOST", "127.0.0.1"),
  database: System.get_env("LA_DB_NAME", "learning_agent_dev"),
  port: String.to_integer(System.get_env("LA_DB_PORT", "5433")),
  pool_size: String.to_integer(System.get_env("LA_POOL_SIZE", "10")),
  show_sensitive_data_on_connection_error: true

if config_env() == :test do
  config :learning_agent,
    http_port: nil,
    worker_slots: 1,
    settings_path: nil,
    local_dogfood: false,
    model_retry_limit: 100,
    model_retry_sleep: false,
    operator_tokens: %{
      "view-token" => {:viewer, "test"},
      "op-token" => {:operator, "test"},
      "admin-token" => {:administrator, "test"}
    }

  config :learning_agent, LearningAgent.Repo,
    database: "learning_agent_test",
    pool: Ecto.Adapters.SQL.Sandbox

  # The scheduler/renewer are OTP loops that own the DB from their own processes;
  # in tests they would fight the per-test sandbox, so they are started explicitly
  # by tests that need them, not by the auto-started application.
  config :learning_agent,
    scheduler: :disabled,
    lease_renewer: :disabled,
    open_viking: :disabled
end

import Config

import Config

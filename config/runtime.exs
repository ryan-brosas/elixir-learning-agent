import Config

# Release-time configuration (docs/04 §config). Loaded by `mix release` runtime.
cbm_port =
  case Integer.parse(System.get_env("LA_CBM_PORT") || "") do
    {port, ""} -> port
    _ -> nil
  end

ov_port =
  case Integer.parse(System.get_env("LA_OV_PORT") || "") do
    {port, ""} -> port
    _ -> nil
  end

if config_env() == :prod do
  config :learning_agent,
    http_port: String.to_integer(System.get_env("LA_HTTP_PORT", System.get_env("PORT", "4000"))),
    skills_root: System.get_env("LA_SKILLS_ROOT", "/agents/skills"),
    source_root: System.get_env("LA_SOURCE_ROOT", "/sources"),
    max_auto_passes: String.to_integer(System.get_env("LA_MAX_AUTO_PASSES", "0")),
    model_retry_limit:
      (case Integer.parse(System.get_env("LA_MODEL_RETRY_LIMIT", "100")) do
         {n, ""} when n in 1..100 -> n
         _ -> 100
       end),
    worker_slots:
      (case Integer.parse(System.get_env("LA_WORKER_SLOTS", "1")) do
         {n, ""} when n in 1..64 -> n
         _ -> 1
       end),
    cbm_host: System.get_env("LA_CBM_HOST"),
    cbm_port: cbm_port,
    ov_host: System.get_env("LA_OV_HOST"),
    ov_port: ov_port

  config :learning_agent, LearningAgent.Repo,
    username: System.get_env("LA_DB_USER", "learning_agent"),
    password: System.get_env("LA_DB_PASS", "learning_agent"),
    hostname: System.get_env("LA_DB_HOST", "postgres"),
    database: System.get_env("LA_DB_NAME", "learning_agent"),
    port: String.to_integer(System.get_env("LA_DB_PORT", "5432")),
    pool_size: String.to_integer(System.get_env("LA_POOL_SIZE", "10"))
end

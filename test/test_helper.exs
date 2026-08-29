ExUnit.start()

# The application (mod: LearningAgent.Application) starts LearningAgent.Repo, so
# here we only place the sandbox into manual mode for per-test isolation.
# (The application's scheduler/renewer are disabled under :test config.)
Ecto.Adapters.SQL.Sandbox.mode(LearningAgent.Repo, :manual)

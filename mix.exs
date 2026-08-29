defmodule LearningAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :learning_agent,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {LearningAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Release config: `mix release` builds an OTP release; bin/server (below) is the
  # container entrypoint that starts the web endpoint and keeps the node alive.
  def releases do
    [
      learning_agent: [
        include_executables_for: [:unix]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:stream_data, "~> 1.0", only: :test},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end
end

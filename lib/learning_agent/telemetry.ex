defmodule LearningAgent.Telemetry do
  @moduledoc """
  Metrics + trace events (docs/04 §17). Declarative event names and an in-memory
  counter sink. No high-cardinality source symbols in labels (docs/04 §24).
  """

  @events [
    "learning_agent.run.start",
    "learning_agent.run.stop",
    "learning_agent.lease.claim",
    "learning_agent.lease.release",
    "learning_agent.model.call"
  ]

  def events, do: @events

  @doc "Emit an event (safe no-op when a sink is not attached)."
  def execute(name, measurements \\ %{}, metadata \\ %{}) when name in @events do
    :telemetry.execute(name, measurements, metadata)
  end

  @doc "Return the /metrics Prometheus-style counters (plain text)."
  def metrics(store) do
    counters = Agent.get(store, & &1)
    Enum.map(counters, fn {name, n} -> format_line(name, n) end) |> Enum.join("\n")
  end

  defp format_line(name, n), do: "learning_agent_" <> String.replace(name, ".", "_") <> " #{n}"
end

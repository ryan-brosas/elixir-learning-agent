defmodule LearningAgent.Domain.Repository do
  @moduledoc """
  Repository lifecycle state machine (docs/01-domain-state-and-closure.md §3).

  Pure domain logic: no side effects, no durable state, no model authority.
  States, transitions, and invariants mirror the accepted design.
  """

  @states [
    :registered,
    :index_unknown,
    :index_ready,
    :active,
    :complete,
    :blocked,
    :stale,
    :disabled
  ]
  @terminal [:complete, :blocked, :disabled]

  # Idempotent adjacencies from design §3 ("Repository transitions").
  @design_transitions %{
    registered: [:index_unknown],
    index_unknown: [:index_ready],
    index_ready: [:active],
    active: [:index_ready, :complete, :blocked],
    complete: [:stale],
    blocked: [:index_ready],
    stale: [:index_unknown]
  }

  @doc "All valid repository states."
  def all_states, do: @states

  @doc "Terminal repository states: closure, standing blocker, or operator-disabled."
  def terminal?(state), do: state in @terminal

  @doc "Direct transitions defined by the lifecycle (excluding operator edges)."
  def design_transitions(from) do
    Map.get(@design_transitions, from, [])
  end

  @doc """
  Whether the state machine permits moving from `from` to `to`.

  Operator edges are permitted for any non-disabled state (disable) and back
  to :index_unknown only from :disabled (enable). Pin change/re-discovery runs
  through the stale -> index_unknown design edge.
  """
  def valid_transition?(from, to) do
    operator_edge?(from, to) or to in design_transitions(from)
  end

  defp operator_edge?(_from, to) when to == :disabled, do: true
  defp operator_edge?(:disabled, :index_unknown), do: true
  defp operator_edge?(_from, _to), do: false

  def valid_state?(state), do: state in @states
end

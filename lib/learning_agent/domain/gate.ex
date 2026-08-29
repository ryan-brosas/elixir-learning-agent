defmodule LearningAgent.Domain.Gate do
  @moduledoc """
  Foundational acceptance gates and their state set (docs/06 § and evidence/planning-sources.md).

  Gates are deterministic; a model never passes a gate. State transitions here are pure.
  """

  @names [
    # source + graph pin verified
    :identity,
    # index coverage and caveats recorded
    :coverage,
    # source + test/probe evidence present for every covered seam
    :evidence,
    # note published, capsules well-formed
    :synthesis,
    # loader, capsule map, and on-disk refs agree
    :parity,
    # deterministic RED/GREEN checks pass
    :pressure,
    # verified generation activated; outbox durable
    :publication
  ]

  @states [:pending, :running, :passed, :failed, :blocked]
  @terminal [:passed, :failed, :blocked]

  @doc "The seven acceptance gates in order."
  def names, do: @names

  @doc "All gate states."
  def states, do: @states

  def terminal?(state), do: state in @terminal
  def passed?(state), do: state == :passed
  def valid_name?(name), do: name in @names
  def valid_state?(state), do: state in @states

  @doc "
  Can a gate advance from `from` to `to`? Only deterministic transitions; a model
  result alone can never mark a gate passed (it only enters :running when it
  proposes; the runtime must confirm).
  "
  def valid_transition?(pending, :running), do: pending == :pending
  def valid_transition?(:running, :failed), do: true
  def valid_transition?(:running, :blocked), do: true
  def valid_transition?(:failed, :passed), do: true
  def valid_transition?(:blocked, :passed), do: true
  def valid_transition?(_from, to) when to == :passed, do: true
  def valid_transition?(_from, _to), do: false
end

defmodule LearningAgent.Domain.Evidence do
  @moduledoc """
  Evidence authority classes and confirmation rules
  (docs/01-domain-state-and-closure.md §8, docs/05-testing-and-verification.md §3).

  Authority classes, strongest-first: probe > direct source > direct test > graph > openviking.
  Graph and OpenViking hits are navigation, never authoritative source confirmation.
  """

  @navigation [:graph, :openviking]
  @authoritative [:probe, :direct_source, :direct_test]
  @all @authoritative ++ @navigation

  @doc "All evidence authority classes, strongest first."
  def all, do: @all

  @doc "Navigation-only surfaces (can never satisfy a source-confirmation requirement)."
  def navigation?(class), do: class in @navigation

  @doc "Authoritative surfaces: can confirm source behavior."
  def authoritative?(class), do: class in @authoritative

  @doc "Can this authority class verify a source/behavior requirement?"
  def satisfies_source_requirement?(class), do: authoritative?(class)

  @doc "Strongest authority among a list (empty -> :none)."
  def strongest(list) when is_list(list) do
    rank = fn
      :probe -> 4
      :direct_source -> 3
      :direct_test -> 2
      :graph -> 1
      :openviking -> 0
      _ -> -1
    end

    case Enum.max_by(List.wrap(list), rank, fn -> :none end) do
      :none -> :none
      max -> max
    end
  end

  @doc "Evidence is decisive for source confirmation only if it came from an authoritative class."
  def decisive_source?(class), do: satisfies_source_requirement?(class)

  # real source anchor (file) is required for any claim
  def valid_class?(class), do: class in @all
end

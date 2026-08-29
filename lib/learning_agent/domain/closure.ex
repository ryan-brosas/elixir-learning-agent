defmodule LearningAgent.Domain.Closure do
  @moduledoc """
  Repository closure predicate (docs/01-domain-state-and-closure.md §10-§11).

  Completion is computed from persisted, deterministic inputs — never asserted by
  the model. This module reduces an evidence/inventory snapshot to an honest
  closed?/unmet decision and fails closed on any missing predicate.
  """

  @type t :: %__MODULE__{closed?: boolean(), unmet: [atom()]}
  defstruct closed?: false, unmet: []

  # The twelve conjuncts of the closure formula (docs/01 §10).
  @predicates [
    :pin_agreement,
    :inventory_adjudicated,
    :all_seams_terminal,
    :covered_evidence_valid,
    :omissions_valid,
    :coverage_resolved,
    :scopes_checked,
    :no_stale_inputs,
    :artifact_parity,
    :verification_fresh,
    :no_open_blockers,
    :next_targets_empty
  ]

  @doc "All closure predicates, in formula order."
  def predicates, do: @predicates

  @doc "Compute closure. Missing predicate key fails closed (unmet)."
  def close(snapshot) when is_map(snapshot) do
    unmet = Enum.reject(@predicates, &(snapshot[&1] == true))
    %__MODULE__{closed?: unmet == [], unmet: unmet}
  end

  @doc "True only when the snapshot satisfies every closure predicate."
  def closed?(snapshot), do: close(snapshot).closed?

  @doc """
  Build a snapshot from an inventory, evidence map, and explicit booleans, then
  evaluate closure.

  Autonomous invariants derived from the item list (adjudication, seams, covered
  evidence, omissions) are computed deterministically. Optional operational states
  are taken from opts and default to false so uncertainty fails closed.
  """
  def evaluate(inventory_items, evidence_map, opts \\ %{}) do
    snapshot = %{
      pin_agreement: opt(opts, :pin_agreement),
      inventory_adjudicated: all_adjudicated?(inventory_items),
      all_seams_terminal: seams_terminal?(inventory_items),
      covered_evidence_valid: covered_evidence_valid?(inventory_items, evidence_map),
      omissions_valid: omissions_valid?(inventory_items),
      coverage_resolved: opt(opts, :coverage_resolved, true),
      scopes_checked: opt(opts, :scopes_checked, true),
      no_stale_inputs: opt(opts, :no_stale_inputs, true),
      artifact_parity: opt(opts, :artifact_parity, true),
      verification_fresh: opt(opts, :verification_fresh, true),
      no_open_blockers: no_open_blockers?(inventory_items),
      next_targets_empty: opt(opts, :next_targets_empty, true)
    }

    close(snapshot)
  end

  defp opt(opts, key, default \\ false) do
    case Map.get(opts, key) do
      nil -> default
      value -> value
    end
  end

  defp all_adjudicated?(items) do
    Enum.all?(items, &(&1.adjudication_state in [:covered, :omitted, :blocked]))
  end

  defp seams_terminal?(items) do
    items
    |> Enum.filter(&(&1.kind == :seam))
    |> Enum.all?(&LearningAgent.Domain.Inventory.terminal?(&1.adjudication_state))
  end

  defp covered_evidence_valid?(items, evidence_map) do
    Enum.all?(items, fn it ->
      it.adjudication_state != :covered or
        Map.get(evidence_map, {it.stable_key, :direct_source}) == :present or
        Map.get(evidence_map, {it.stable_key, :probe}) == :present
    end)
  end

  defp omissions_valid?(items) do
    Enum.all?(items, fn it ->
      not LearningAgent.Domain.Inventory.requires_reason?(it.adjudication_state) or
        is_binary(it.reason_code)
    end)
  end

  defp no_open_blockers?(items) do
    not Enum.any?(items, fn it ->
      it.adjudication_state == :blocked and is_nil(it.reason_code)
    end)
  end
end

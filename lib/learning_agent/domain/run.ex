defmodule LearningAgent.Domain.Run do
  @moduledoc """
  Run lifecycle state machine (docs/01-domain-state-and-closure.md §4).

  Pure domain: no SQL, no processes, no model access. Guards for
  note-first, cancel-before-start, and lease invariants belong here.
  """

  @states [
    :queued,
    :claimed,
    :preflight,
    :note_drafting,
    :note_published,
    :exploring,
    :evidence_gathering,
    :synthesizing,
    :validating,
    :publishing,
    :recording_result,
    :cancel_requested
  ]

  @terminal [:completed, :partial, :blocked, :failed, :cancelled, :orphaned]
  @all @states ++ @terminal

  # Allowed transitions. The model/loop may only act according to the current
  # gate; validity is a pure predicate, never delegated to the model.
  @transitions %{
    queued: [:claimed, :cancelled],
    claimed: [:preflight, :cancelled],
    preflight: [:note_drafting, :blocked, :failed, :cancelled, :orphaned],
    note_drafting: [:note_published, :blocked, :failed, :cancelled, :orphaned],
    note_published: [:exploring, :blocked, :failed, :cancelled, :orphaned],
    exploring: [:evidence_gathering, :blocked, :failed, :cancelled, :orphaned],
    evidence_gathering: [:synthesizing, :blocked, :failed, :cancelled, :orphaned],
    synthesizing: [:validating, :blocked, :failed, :cancelled, :orphaned],
    validating: [:publishing, :blocked, :failed, :cancelled, :orphaned],
    publishing: [:recording_result, :blocked, :failed, :cancelled, :orphaned],
    recording_result: [:completed, :partial, :blocked, :failed, :cancelled, :orphaned],
    cancel_requested: [:cancelled]
  }

  @doc "All run states, including terminals."
  def all_states, do: @all

  @doc "Terminal states where the run stops."
  def terminal?(state), do: state in @terminal

  @doc "Success-terminal states (observed, valid result committed)."
  def success_terminal?(state), do: state in [:completed, :partial]

  @doc "In-flight (non-terminal) states that still own durable work."
  def non_terminal?(state), do: state in @states

  @doc "States from which the worker may still be making external calls."
  def cancellable?(state), do: non_terminal?(state) or state == :cancel_requested

  def transitions(state), do: Map.get(@transitions, state, [])

  def valid_transition?(from, to), do: to in transitions(from)

  def valid_state?(state), do: state in @all
end

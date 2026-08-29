defmodule LearningAgent.Domain.RunTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.Run

  test "happy path transitions are valid" do
    assert Run.valid_transition?(:queued, :claimed)
    assert Run.valid_transition?(:claimed, :preflight)
    assert Run.valid_transition?(:preflight, :note_drafting)
    assert Run.valid_transition?(:note_drafting, :note_published)
    assert Run.valid_transition?(:note_published, :exploring)
    assert Run.valid_transition?(:exploring, :evidence_gathering)
    assert Run.valid_transition?(:evidence_gathering, :synthesizing)
    assert Run.valid_transition?(:synthesizing, :validating)
    assert Run.valid_transition?(:validating, :publishing)
    assert Run.valid_transition?(:publishing, :recording_result)
    assert Run.valid_transition?(:recording_result, :completed)
  end

  test "note-first invariant: synthesizing cannot be reached without note_published" do
    refute Run.valid_transition?(:note_drafting, :synthesizing)
    refute Run.valid_transition?(:preflight, :synthesizing)
    refute Run.valid_transition?(:exploring, :synthesizing)
  end

  test "lease invariant: only claimed can progress to preflight" do
    refute Run.valid_transition?(:queued, :preflight)
    assert Run.valid_transition?(:claimed, :preflight)
  end

  test "cancellation is reachable from every non-terminal state" do
    assert Run.valid_transition?(:cancel_requested, :cancelled)

    for s <- Run.all_states(),
        s not in [:completed, :partial, :blocked, :failed, :cancelled, :orphaned] do
      assert :cancelled in Run.transitions(s), "expected #{s} to allow cancellation"
    end
  end

  test "terminal states are terminal" do
    for s <- [:completed, :partial, :blocked, :failed, :cancelled, :orphaned] do
      assert Run.terminal?(s)
      refute Run.non_terminal?(s)
    end
  end

  test "success terminals are exactly completed and partial" do
    assert Run.success_terminal?(:completed)
    assert Run.success_terminal?(:partial)
    refute Run.success_terminal?(:blocked)
  end
end

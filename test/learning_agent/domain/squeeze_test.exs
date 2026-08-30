defmodule LearningAgent.Domain.SqueezeTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.Squeeze

  @arch """
  # architecture
  Repository `demo` at `/src` (graph `demo`), pass 1.
  Layout captured.

  # covered
  - `lib/`

  # partial/uncited
  - `lib/mod.ex`

  # porter-questions
  What first reusable seam?

  # selected-subsystem
  lib/
  """

  @file_note """
  # architecture
  Repository `demo` at `/src` (graph `demo`), pass 2.

  # covered
  - `lib/mod.ex`

  # partial/uncited
  No unread source files remain; this repository is drained.

  # porter-questions
  q

  # selected-subsystem
  lib/mod.ex
  """

  test "is not closed until architecture plus every component and file are covered" do
    inventory = ["lib/", "lib/mod.ex"]
    refute Squeeze.closed?(inventory, [@arch])
    assert Squeeze.uncovered(inventory, [@arch]) == ["lib/mod.ex"]
    assert Squeeze.closed?(inventory, [@arch, @file_note])
    assert Squeeze.architecture_recorded?([@arch])
  end

  test "a visited empty inventory is drained so a vanished source cannot hot-loop" do
    refute Squeeze.closed?([], [])
    assert Squeeze.closed?([], [@arch])
  end
end

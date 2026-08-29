defmodule LearningAgent.Notes.ValidatorTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Notes.Validator

  test "a complete note passes" do
    assert :ok =
             Validator.validate(
               "# architecture\n# covered\n# partial/uncited\n# porter-questions\n# selected-subsystem"
             )
  end

  test "a note missing a section is rejected with the missing list" do
    assert {:error, missing} = Validator.validate("# architecture only")
    assert "partial/uncited" in missing
  end
end

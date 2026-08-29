defmodule LearningAgent.ToolPolicyTest do
  use ExUnit.Case, async: true
  alias LearningAgent.ToolPolicy

  defp ctx(gate), do: %{gate: gate, root: "/repos/r", run_id: "r1"}

  test "unknown tool is denied" do
    assert {:deny, :unknown_tool} = ToolPolicy.evaluate("nuke.launch", %{}, ctx(:exploring))
  end

  test "a tool at the wrong gate is denied" do
    assert {:allow, _} =
             ToolPolicy.evaluate("learning.publish_note", %{content: "x"}, ctx(:note_drafting))

    assert {:deny, :wrong_gate} =
             ToolPolicy.evaluate("learning.publish_note", %{}, ctx(:exploring))
  end

  test "an unregistered tool is never allowed (denied as unknown)" do
    assert {:deny, :unknown_tool} = ToolPolicy.evaluate("bad.rm", %{}, ctx(:exploring))
  end

  test "a forbidden token in a registered tool arg is denied" do
    assert {:deny, :forbidden_capability} =
             ToolPolicy.evaluate("graph.search", %{query: "run apt-get update"}, ctx(:exploring))
  end

  test "shell fragment smuggled in a nominally-safe arg is denied" do
    assert {:deny, :forbidden_capability} =
             ToolPolicy.evaluate("graph.search", %{query: "; rm -rf /"}, ctx(:exploring))
  end

  test "source.read_range with a traversal path is denied" do
    assert {:deny, {:path_escape, :traversal}} =
             ToolPolicy.evaluate(
               "source.read_range",
               %{relative_path: "../../etc/passwd"},
               ctx(:evidence_gathering)
             )
  end

  test "source.read_range with a clean path is allowed" do
    assert {:allow, %{relative_path: "lib/x.ex"}} =
             ToolPolicy.evaluate(
               "source.read_range",
               %{relative_path: "lib/x.ex", start_line: 1, end_line: 5},
               ctx(:evidence_gathering)
             )
  end

  test "source.read_range missing path is denied" do
    assert {:deny, :missing_relative_path} =
             ToolPolicy.evaluate("source.read_range", %{start_line: 1}, ctx(:evidence_gathering))
  end
end

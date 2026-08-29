defmodule LearningAgent.ArtifactsTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Artifacts.{Publisher, Stager, Journal}

  defp work_root do
    Path.join(
      System.tmp_dir!(),
      "la_art_" <> Integer.to_string(System.unique_integer([:positive]))
    )
  end

  defp files, do: %{"SKILL.md" => "# leaf", "references/retry.md" => "<!-- capsule-v2 -->"}

  test "publish stages, activates, verifies and commits a generation" do
    root = work_root()
    {:ok, %{active: active}} = Publisher.publish(root, "gen-1", files())
    assert File.exists?(Path.join(active, "SKILL.md"))
    assert File.exists?(Path.join(active, "references/retry.md"))
    assert File.exists?(Path.join(root, "committed_gen-1"))
    assert length(Journal.read(root)) == 1
    File.rm_rf!(root)
  end

  test "staging rejects an unexpected top-level file" do
    root = work_root()
    assert {:error, :unexpected_file} = Stager.stage(root, "g", %{"evil.sh" => "exit 0"})
    File.rm_rf!(root)
  end

  test "stager accepts canonical leaf + references files" do
    root = work_root()
    assert {:ok, staged} = Stager.stage(root, "g", %{"SKILL.md" => "x", "references/a.md" => "y"})
    assert staged.manifest.manifest_digest
    File.rm_rf!(root)
  end
end

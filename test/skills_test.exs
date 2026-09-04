defmodule LearningAgent.SkillsTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Skills.{Capsule, Synthesizer, Leaf}

  defp capsule do
    Capsule.new(%{
      seam: "adapter-singleflight",
      source: "requests (Apache) at main@abc; CBM requests",
      question: "How does the adapter dedupe concurrent identical calls?",
      path_symbol: "src/requests/adapters.py:RequestAdapter",
      direct_source_excerpt: "class adapter... def _perform(req)",
      source_digest:
        :crypto.hash(:sha256, "class adapter... def _perform(req)")
        |> Base.encode16(case: :lower),
      source_revision: "abc",
      test_evidence: "test/adapters_test.py::test_singleflight",
      boundary: "request adapter",
      invariant: "never two concurrent sends",
      limits: "transport-specific",
      verdict: "adopt singleflight; adapt host transport"
    })
  end

  test "a complete capsule validates" do
    assert :ok = Capsule.validate(capsule())
  end

  test "validate rejects a capsule missing a field" do
    c = capsule()
    assert {:error, missing} = Capsule.validate(%{c | invariant: nil})
    assert :invariant in missing
  end

  test "validate rejects a digest that does not bind the direct excerpt" do
    assert {:error, [:source_digest]} =
             capsule() |> Map.put(:source_digest, String.duplicate("0", 64)) |> Capsule.validate()
  end

  test "synthesizer renders a capsule with the canonical header and verdict" do
    md = Synthesizer.render_capsule(capsule())
    assert md =~ "<!-- capsule-v2 -->"
    assert md =~ "## Verdict"
    assert md =~ "adapter-singleflight"
  end

  test "capsule ref convention matches the loader" do
    assert Synthesizer.capsule_ref("retry") == "references/retry.md"
  end

  test "leaf parity passes when loader, map, and disk agree" do
    refs = ["references/a.md", "references/b.md"]
    assert :ok = Leaf.check_parity(refs, refs, refs)
  end

  test "leaf parity detects a loader/map mismatch" do
    refs = ["references/a.md"]

    assert {:error, :loader_map_mismatch} =
             Leaf.check_parity(refs, ["references/a.md", "references/b.md"], refs)
  end

  test "leaf parity detects a disk mismatch" do
    refs = ["references/a.md"]
    assert {:error, :disk_mismatch} = Leaf.check_parity(refs, refs, [])
  end

  test "refs_from_loader extracts the reference list from a loader block" do
    loader = "- `references/a.md` — a porting question.\n- `references/b.md` — another."
    assert ["references/a.md", "references/b.md"] = Leaf.refs_from_loader(loader)
  end

  test "activated? accepts a real dir with SKILL.md" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "la_skill_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "SKILL.md"), "# leaf")
    assert LearningAgent.Skills.Leaf.activated?(dir)
    File.rm_rf!(dir)
  end

  test "activated? accepts a symlink leaf pointing to a SKILL.md (atomic swap viable)" do
    gen =
      Path.join(
        System.tmp_dir!(),
        "la_gen_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    link =
      Path.join(
        System.tmp_dir!(),
        "la_link_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(gen)
    File.write!(Path.join(gen, "SKILL.md"), "# v1")
    File.ln_s!(gen, link)
    assert LearningAgent.Skills.Leaf.activated?(link)
    File.rm!(link)
    File.rm_rf!(gen)
  end
end

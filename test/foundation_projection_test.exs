defmodule LearningAgent.FoundationProjectionTest do
  use ExUnit.Case, async: true

  alias LearningAgent.Artifacts.{Manifest, Publisher}
  alias LearningAgent.Foundations.Projection
  alias LearningAgent.{Repository, ToolRegistry}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "la_projection_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "zero-capsule projection is a YAML-safe manual foundation and never a procedure" do
    repository = repository("safe", "Safe: value # one\ntwo")
    assert {:ok, files} = Projection.files(repository, [])
    skill = files["SKILL.md"]

    assert skill =~ ~s(name: "safe-foundation")

    assert skill =~
             ~s(description: "Stable direct-evidence foundation for Safe: value # one\\ntwo")

    assert skill =~ "kind: foundation"
    assert skill =~ "invocation: manual"
    assert skill =~ "disable-model-invocation: true"
    assert skill =~ "producer: elixir-learning-agent"
    assert skill =~ "projection-version: 1"
    refute skill =~ "kind: procedure"
    assert skill =~ "No accepted seam capsules exist"
    assert Map.keys(files) |> Enum.reject(&(&1 in ["SKILL.md", Publisher.owner_file()])) == []
  end

  test "stable seam identity is independent of pass number" do
    key = Projection.stable_key("lib/router.ex")
    assert key == Projection.stable_key("lib/router.ex")
    refute key =~ "pass"
    refute key =~ "-1"
  end

  test "manifest identity includes file content" do
    first = Manifest.build(%{"SKILL.md" => "one"})
    second = Manifest.build(%{"SKILL.md" => "two"})
    refute first.manifest_digest == second.manifest_digest
  end

  test "publisher activates only the foundation path and is content-idempotent", %{root: root} do
    assert {:ok, files} = Projection.files(repository("demo", "Demo"), [])
    assert {:ok, first} = Publisher.publish_foundation(root, "demo", files)
    assert first.active == Path.join(root, "demo-foundation")
    refute first.unchanged
    assert File.exists?(Path.join(first.active, "SKILL.md"))

    assert {:ok, second} = Publisher.publish_foundation(root, "demo", files)
    assert second.manifest_digest == first.manifest_digest
    assert second.unchanged
  end

  test "recovery restores a missing active link from the immutable generation", %{root: root} do
    assert {:ok, files} = Projection.files(repository("recoverable", "Recoverable"), [])
    assert {:ok, published} = Publisher.publish_foundation(root, "recoverable", files)
    File.rm!(published.active)

    assert {:ok, recovered} =
             Publisher.recover_foundation(root, "recoverable", published.manifest_digest)

    assert File.exists?(Path.join(recovered.active, "SKILL.md"))
  end

  test "unmanaged destination is preserved and reported as a conflict", %{root: root} do
    destination = Path.join(root, "owned-foundation")
    File.mkdir_p!(destination)
    sentinel = Path.join(destination, "do-not-touch.txt")
    File.write!(sentinel, "human")
    assert {:ok, files} = Projection.files(repository("owned", "Owned"), [])

    assert {:error, :artifact_conflict} = Publisher.publish_foundation(root, "owned", files)
    assert File.read!(sentinel) == "human"
  end

  test "unmanaged legacy leaf is preserved and reported as a conflict", %{root: root} do
    legacy = Path.join(root, "legacy")
    File.mkdir_p!(legacy)
    sentinel = Path.join(legacy, "SKILL.md")
    File.write!(sentinel, "# human skill")
    assert {:ok, files} = Projection.files(repository("legacy", "Legacy"), [])

    assert {:error, :artifact_conflict} = Publisher.publish_foundation(root, "legacy", files)
    assert File.read!(sentinel) == "# human skill"
  end

  test "a proven managed legacy leaf is archived before foundation activation", %{root: root} do
    legacy = Path.join(root, "migrated")
    File.mkdir_p!(Path.join(legacy, "references"))

    File.write!(Path.join(legacy, "SKILL.md"), """
    ## Loader
    - `references/old.md` — a porting question.
    ## Capsule map
    - **Capability** — `references/old.md`: reusable contract.
    """)

    File.write!(Path.join([legacy, "references", "old.md"]), "<!-- capsule-v2 -->\nold")
    assert {:ok, files} = Projection.files(repository("migrated", "Migrated"), [])
    assert {:ok, published} = Publisher.publish_foundation(root, "migrated", files)

    refute File.exists?(legacy)
    assert File.exists?(Path.join(published.active, "SKILL.md"))
    assert File.exists?(Path.join([root, ".learning-agent", "legacy", "migrated", "SKILL.md"]))
  end

  test "automatic execution has no Store activation bypass" do
    pass_source = File.read!("lib/learning_agent/learning_pass.ex")
    store_source = File.read!("lib/learning_agent/skills/store.ex")

    refute pass_source =~ "Store.write_leaf"
    assert store_source =~ "Publisher.publish_foundation"
    refute Enum.any?(ToolRegistry.all(), &String.contains?(&1, "procedure"))
    refute ToolRegistry.registered?("artifacts.propose_leaf")
  end

  defp repository(slug, name), do: %Repository{slug: slug, display_name: name}
end

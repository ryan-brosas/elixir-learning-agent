defmodule LearningAgent.Skills.RootTest do
  use ExUnit.Case, async: false
  alias LearningAgent.Skills.{Root, Store}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "la_skills_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    previous = Application.get_env(:learning_agent, :skills_root)
    Application.put_env(:learning_agent, :skills_root, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :skills_root),
        else: Application.put_env(:learning_agent, :skills_root, previous)
    end)

    %{root: root}
  end

  test "ensure falls back when the configured root is not writable" do
    locked =
      Path.join(
        System.tmp_dir!(),
        "la_locked_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(locked)
    File.chmod!(locked, 0o500)
    previous = Application.get_env(:learning_agent, :skills_root)
    Application.put_env(:learning_agent, :skills_root, Path.join(locked, "skills"))

    try do
      assert :ok = Root.ensure()

      assert String.ends_with?(Root.path(), "skills-data") or
               File.stat!(Root.path()).access == :read_write
    after
      File.chmod!(locked, 0o700)
      File.rm_rf!(locked)
      Application.put_env(:learning_agent, :skills_root, previous)
    end
  end

  test "contain rejects path escape", %{root: root} do
    assert {:error, :path_escape} = Root.contain("../etc/passwd")
    assert {:ok, dest} = Root.contain("demo")
    assert String.starts_with?(dest, root)
  end

  test "store writes a leaf only under the skills root", %{root: root} do
    skill = """
    ## Loader
    - `references/demo.md` — a porting question.

    ## Capsule map
    - **Capability** — `references/demo.md`: reusable contract.
    """

    assert {:ok, dest} =
             Store.write_leaf("demo", %{
               "SKILL.md" => skill,
               "references/demo.md" => "capsule"
             })

    assert dest == Path.join(root, "demo")
    assert File.exists?(Path.join(dest, "SKILL.md"))
    refute File.exists?(Path.join(Path.dirname(root), "demo"))
  end
end

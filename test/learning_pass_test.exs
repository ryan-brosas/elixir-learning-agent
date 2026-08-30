defmodule LearningAgent.LearningPassTest do
  use LearningAgent.DataCase, async: false
  alias LearningAgent.{LearningPass, RepositoryContext, RunContext}

  setup do
    work =
      Path.join(
        System.tmp_dir!(),
        "la_pass_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    src = Path.join(work, "src")
    skills = Path.join(work, "skills")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "mod.ex"), "defmodule Observed, do: :ok\n")

    prev_skills = Application.get_env(:learning_agent, :skills_root)
    prev_source = Application.get_env(:learning_agent, :source_root)
    prev_max = Application.get_env(:learning_agent, :max_auto_passes)
    Application.put_env(:learning_agent, :skills_root, skills)
    Application.put_env(:learning_agent, :source_root, src)
    Application.put_env(:learning_agent, :max_auto_passes, 1)

    on_exit(fn ->
      File.rm_rf!(work)
      restore(:skills_root, prev_skills)
      restore(:source_root, prev_source)
      restore(:max_auto_passes, prev_max)
    end)

    %{src: src, skills: skills}
  end

  test "a claimed run publishes a note then a skill under the locked root", %{
    src: src,
    skills: skills
  } do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "observed",
        display_name: "Observed",
        graph_project: "observed",
        source_locator: src
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{root: src, branch: "main", commit_sha: "abc"})

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)
    {:ok, claimed, _lease} = RunContext.claim(run)

    assert {:ok, result} = LearningPass.execute(claimed)
    assert result.run.state == "completed"
    assert File.exists?(result.note)
    assert result.skill == Path.join(skills, "observed")
    assert File.exists?(Path.join(result.skill, "SKILL.md"))
    assert File.exists?(Path.join(result.skill, "references/observed-pass-1.md"))
    assert File.read!(result.note) =~ "selected-subsystem"
  end

  test "keeps queueing passes until unread source files are gone", %{src: src} do
    File.write!(Path.join(src, "alpha.ex"), "defmodule Alpha, do: :ok\n")
    File.write!(Path.join(src, "beta.ex"), "defmodule Beta, do: :ok\n")
    Application.put_env(:learning_agent, :max_auto_passes, 0)

    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "drain-me",
        display_name: "Drain Me",
        graph_project: "drain-me",
        source_locator: src
      })

    {:ok, run} =
      RepositoryContext.queue_pass(repo.id, %{root: src, branch: "main", commit_sha: "abc"})

    {:ok, claimed, _} = RunContext.claim(run)
    assert {:ok, _} = LearningPass.execute(claimed)

    Enum.each(1..5, fn _ ->
      case RunContext.active_for(repo.id) do
        %{state: "queued"} = queued ->
          {:ok, next, _} = RunContext.claim(queued)
          assert {:ok, _} = LearningPass.execute(next)

        _ ->
          :ok
      end
    end)

    repo = RepositoryContext.get(repo.id)
    assert repo.status == "complete"
    refute RunContext.active_for(repo.id)
  end

  defp restore(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore(key, value), do: Application.put_env(:learning_agent, key, value)
end

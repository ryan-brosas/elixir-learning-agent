defmodule LearningAgent.FoundationProjectionRegressionTest do
  use LearningAgent.DataCase, async: false

  import Ecto.Query

  alias LearningAgent.{
    ArtifactSet,
    Foundations,
    LearningPass,
    OutboxEvent,
    Repo,
    RepositoryContext,
    RunContext
  }

  setup do
    work =
      Path.join(
        System.tmp_dir!(),
        "la_foundation_regression_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    source = Path.join(work, "source")
    skills = Path.join(work, "skills")
    File.mkdir_p!(source)
    File.write!(Path.join(source, "alpha.ex"), "defmodule Alpha, do: :alpha\n")
    File.write!(Path.join(source, "beta.ex"), "defmodule Beta, do: :beta\n")

    previous = %{
      skills: Application.get_env(:learning_agent, :skills_root),
      source: Application.get_env(:learning_agent, :source_root),
      max: Application.get_env(:learning_agent, :max_auto_passes),
      model: Application.get_env(:learning_agent, :model),
      complete: Application.get_env(:learning_agent, :note_complete)
    }

    Application.put_env(:learning_agent, :skills_root, skills)
    Application.put_env(:learning_agent, :source_root, source)
    Application.put_env(:learning_agent, :max_auto_passes, 1)

    on_exit(fn ->
      File.rm_rf!(work)
      restore(:skills_root, previous.skills)
      restore(:source_root, previous.source)
      restore(:max_auto_passes, previous.max)
      restore(:model, previous.model)
      restore(:note_complete, previous.complete)
    end)

    %{source: source, skills: skills}
  end

  test "a second pass preserves the first seam reference", %{source: source, skills: skills} do
    {:ok, repo} = register("preserve-seams", source)
    {:ok, first} = RepositoryContext.queue_pass(repo.id, pin(source))
    {:ok, first, _lease} = RunContext.claim(first)
    assert {:ok, _} = LearningPass.execute(first)

    {:ok, second} = RepositoryContext.queue_pass(repo.id)
    {:ok, second, _lease} = RunContext.claim(second)
    assert {:ok, _} = LearningPass.execute(second)

    foundation = Path.join(skills, "preserve-seams-foundation")
    references = Path.join([foundation, "references", "*.md"])
    assert length(Path.wildcard(references)) == 2
    refute Enum.any?(Path.wildcard(references), &String.contains?(&1, "pass-"))

    skill = File.read!(Path.join(foundation, "SKILL.md"))
    assert skill =~ "kind: foundation"
    refute skill =~ "kind: procedure"

    assert Repo.aggregate(ArtifactSet, :count, :id) == 2

    events =
      from(event in OutboxEvent,
        where: event.repository_id == ^repo.id and event.event_type == "materialize_foundation"
      )
      |> Repo.all()

    assert Enum.all?(events, &String.starts_with?(&1.destination, "foundations/preserve-seams/"))
    assert Enum.all?(events, &(&1.payload["authority"] == false))
    assert Enum.all?(events, &(&1.payload["current_memory"] == false))

    assert Enum.all?(events, fn event ->
             event.payload["path"] =~ "/.learning-agent/generations/preserve-seams-foundation/" and
               File.dir?(event.payload["path"])
           end)
  end

  test "reusing a cached projection repairs and relinks the active foundation", %{
    source: source,
    skills: skills
  } do
    {:ok, repo} = register("cache-repair", source)
    {:ok, first_run} = RepositoryContext.queue_pass(repo.id, pin(source))
    first_pin_id = first_run.pin_id
    {:ok, first_claimed, _lease} = RunContext.claim(first_run)
    assert {:ok, first} = LearningPass.execute(first_claimed)

    File.write!(Path.join(source, "alpha.ex"), "defmodule Alpha, do: :changed\n")

    {:ok, second_run} =
      RepositoryContext.queue_pass(repo.id, %{
        root: source,
        branch: "main",
        commit_sha: "def456"
      })

    {:ok, second_claimed, _lease} = RunContext.claim(second_run)
    assert {:ok, second} = LearningPass.execute(second_claimed)
    refute second.manifest_digest == first.manifest_digest

    {:ok, replay_run} = RunContext.create(repo.id, first_pin_id, 3)
    assert {:ok, replayed} = Foundations.project(RepositoryContext.get(repo.id), replay_run, nil)
    refute replayed.unchanged
    assert replayed.manifest_digest == first.manifest_digest

    expected_generation =
      Path.join([
        skills,
        ".learning-agent",
        "generations",
        "cache-repair-foundation",
        first.manifest_digest
      ])

    {:ok, target} = File.read_link(replayed.active)
    assert Path.expand(target, Path.dirname(replayed.active)) == expected_generation

    File.rm!(replayed.active)
    {:ok, repair_run} = RunContext.create(repo.id, first_pin_id, 4)
    assert {:ok, repaired} = Foundations.project(RepositoryContext.get(repo.id), repair_run, nil)
    refute repaired.unchanged
    assert File.exists?(Path.join(repaired.active, "SKILL.md"))
  end

  test "the model prompt does not receive the full prior note", %{source: source} do
    {:ok, repo} = register("bounded-context", source)
    test_pid = self()

    Application.put_env(:learning_agent, :model,
      enabled: true,
      base_url: "http://stub.local/v1",
      model: "stub-model",
      api_key: nil,
      timeout_ms: 1_000
    )

    Application.put_env(:learning_agent, :note_complete, fn payload ->
      send(test_pid, {:prompt, payload})
      {:error, %{class: :timeout}}
    end)

    observation = %{
      selected: "alpha.ex",
      files: ["alpha.ex"],
      memory: "ready",
      architecture: nil,
      component: nil,
      remaining: 0,
      prior: %{note: "FULL_PRIOR_NOTE_MUST_NOT_BE_INJECTED", count: 1}
    }

    assert :fallback = LearningPass.learn(repo, %{pass_number: 2}, observation, "stub-model")
    assert_received {:prompt, payload}
    prompt = payload.messages |> hd() |> Map.fetch!(:content) |> hd() |> Map.fetch!(:text)
    refute prompt =~ "FULL_PRIOR_NOTE_MUST_NOT_BE_INJECTED"
  end

  defp register(slug, source) do
    RepositoryContext.register(%{
      slug: slug,
      display_name: slug,
      graph_project: slug,
      source_locator: source
    })
  end

  defp pin(source), do: %{root: source, branch: "main", commit_sha: "abc123"}

  defp restore(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore(key, value), do: Application.put_env(:learning_agent, key, value)
end

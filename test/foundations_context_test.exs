defmodule LearningAgent.FoundationsContextTest do
  use LearningAgent.DataCase, async: true

  alias LearningAgent.{
    FoundationCapsule,
    Foundations,
    RepositoryContext,
    RunContext
  }

  test "pass observation and accepted seam append idempotently without pass-number identity" do
    {repository, pin} = repository_and_pin("immutable")
    {:ok, run} = RunContext.create(repository.id, pin.id, 1)
    attrs = observation_attrs(repository.id, pin.id, run.id, 1, "lib/router.ex", "abc")

    assert {:ok, observation} = Foundations.record_observation(attrs)
    assert {:ok, same_observation} = Foundations.record_observation(attrs)
    assert same_observation.id == observation.id

    changed = put_in(attrs, [:direct_evidence, "excerpt"], "changed")
    assert {:error, :observation_conflict} = Foundations.record_observation(changed)

    assert {:ok, capsule} = Foundations.accept_observed_seam(observation)
    assert {:ok, same_capsule} = Foundations.accept_observed_seam(observation)
    assert same_capsule.id == capsule.id
    refute capsule.stable_key =~ "pass"
    refute capsule.stable_key =~ "-1"
    assert capsule.source_excerpt == "def call(request), do: request"
    assert capsule.source_digest == LearningAgent.Notes.digest(capsule.source_excerpt)
    assert capsule.source_revision == "abc"
    assert capsule.test_caveat =~ "No direct test"
  end

  test "one observation can accept multiple directly evidenced seams" do
    {repository, pin} = repository_and_pin("multiple")
    {:ok, run} = RunContext.create(repository.id, pin.id, 1)

    seams =
      Enum.map(["lib/router.ex", "lib/worker.ex"], fn path ->
        excerpt = "defmodule #{Path.basename(path, ".ex")}, do: :ok"

        %{
          "source_path" => path,
          "excerpt" => excerpt,
          "digest" => LearningAgent.Notes.digest(excerpt),
          "revision" => "abc",
          "test_caveat" => "No direct test observed",
          "question" => "What is stable?",
          "boundary" => path,
          "invariant" => "returns ok",
          "limits" => "excerpt only"
        }
      end)

    attrs =
      observation_attrs(repository.id, pin.id, run.id, 1, "lib/router.ex", "abc")
      |> Map.put(:source_paths, Enum.map(seams, & &1["source_path"]))
      |> Map.put(:direct_evidence, %{"seams" => seams})

    {:ok, observation} = Foundations.record_observation(attrs)
    assert {:ok, capsules} = Foundations.accept_observed_seams(observation)
    assert Enum.map(capsules, & &1.source_path) == ["lib/router.ex", "lib/worker.ex"]
    assert length(Foundations.accepted_capsules(repository.id, pin.id)) == 2
  end

  test "multiple seam acceptance rolls back when any seam conflicts" do
    {repository, pin} = repository_and_pin("atomic-seams")
    {:ok, first_run} = RunContext.create(repository.id, pin.id, 1)

    first_attrs =
      observation_attrs(repository.id, pin.id, first_run.id, 1, "lib/worker.ex", "abc")

    {:ok, first_observation} = Foundations.record_observation(first_attrs)
    assert {:ok, [_]} = Foundations.accept_observed_seams(first_observation)

    {:ok, second_run} = RunContext.create(repository.id, pin.id, 2)

    router =
      observation_attrs(repository.id, pin.id, second_run.id, 2, "lib/router.ex", "abc").direct_evidence

    conflicting_worker =
      first_attrs.direct_evidence
      |> Map.put("excerpt", "changed behavior")
      |> Map.put("digest", LearningAgent.Notes.digest("changed behavior"))

    second_attrs =
      observation_attrs(repository.id, pin.id, second_run.id, 2, "lib/router.ex", "abc")
      |> Map.put(:source_paths, ["lib/router.ex", "lib/worker.ex"])
      |> Map.put(:direct_evidence, %{"seams" => [router, conflicting_worker]})

    {:ok, second_observation} = Foundations.record_observation(second_attrs)
    assert {:error, :capsule_conflict} = Foundations.accept_observed_seams(second_observation)

    assert Enum.map(Foundations.accepted_capsules(repository.id, pin.id), & &1.source_path) == [
             "lib/worker.ex"
           ]
  end

  test "a capsule requires direct test evidence or an explicit caveat" do
    changeset =
      FoundationCapsule.changeset(%FoundationCapsule{}, %{
        repository_id: Ecto.UUID.generate(),
        pin_id: Ecto.UUID.generate(),
        observation_id: Ecto.UUID.generate(),
        stable_key: "router",
        source_path: "router.ex",
        source_excerpt: "source",
        source_digest: :crypto.hash(:sha256, "source") |> Base.encode16(case: :lower),
        source_revision: "abc",
        question: "what?",
        boundary: "router",
        invariant: "one route",
        limits: "excerpt only",
        status: "accepted"
      })

    refute changeset.valid?
    assert {"test evidence or an explicit caveat is required", _} = changeset.errors[:test_caveat]
  end

  test "prior context is bounded and scoped to the current pin" do
    {repository, first_pin} = repository_and_pin("bounded")

    for pass <- 1..30 do
      {:ok, run} = RunContext.create(repository.id, first_pin.id, pass)
      path = "lib/file_#{pass}.ex"
      attrs = observation_attrs(repository.id, first_pin.id, run.id, pass, path, "old-pin")
      {:ok, observation} = Foundations.record_observation(attrs)
      {:ok, _} = Foundations.accept_observed_seam(observation)
    end

    {:ok, second_pin} =
      RepositoryContext.add_pin(repository.id, %{
        root: repository.source_locator,
        branch: "main",
        commit_sha: "new-pin"
      })

    {:ok, run} = RunContext.create(repository.id, second_pin.id, 31)
    attrs = observation_attrs(repository.id, second_pin.id, run.id, 31, "lib/new.ex", "new-pin")
    {:ok, observation} = Foundations.record_observation(attrs)
    {:ok, _} = Foundations.accept_observed_seam(observation)

    context = Foundations.prior_context(repository.id, second_pin.id)
    assert byte_size(context.text) <= 8_192
    assert context.coverage == ["lib/new.ex"]
    assert Enum.map(context.seams, & &1.path) == ["lib/new.ex"]
    refute context.text =~ "old-pin"
    refute context.text =~ "file_1.ex"
  end

  test "a zero-capsule pass is a valid immutable observation" do
    {repository, pin} = repository_and_pin("zero")
    {:ok, run} = RunContext.create(repository.id, pin.id, 1)

    attrs = %{
      repository_id: repository.id,
      run_id: run.id,
      pin_id: pin.id,
      pass_number: 1,
      source_paths: [],
      direct_evidence: %{},
      model: nil,
      coverage: %{"remaining" => 0},
      unresolved: ["No source was available"],
      omissions: [],
      observed_at: DateTime.utc_now()
    }

    assert {:ok, observation} = Foundations.record_observation(attrs)
    assert {:ok, nil} = Foundations.accept_observed_seam(observation)
    assert Foundations.accepted_capsules(repository.id, pin.id) == []
  end

  defp repository_and_pin(slug) do
    {:ok, repository} =
      RepositoryContext.register(%{
        slug: slug,
        display_name: slug,
        graph_project: slug,
        source_locator: "/sources/#{slug}"
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repository.id, %{
        root: repository.source_locator,
        branch: "main",
        commit_sha: "abc"
      })

    {repository, pin}
  end

  defp observation_attrs(repository_id, pin_id, run_id, pass, path, revision) do
    excerpt = "def call(request), do: request"

    %{
      repository_id: repository_id,
      run_id: run_id,
      pin_id: pin_id,
      pass_number: pass,
      source_paths: [path],
      direct_evidence: %{
        "source_path" => path,
        "excerpt" => excerpt,
        "digest" => LearningAgent.Notes.digest(excerpt),
        "revision" => revision,
        "test_caveat" => "No direct test observed",
        "question" => "What does this boundary expose?",
        "boundary" => path,
        "invariant" => "request is returned",
        "limits" => "excerpt only"
      },
      model: "test-model",
      coverage: %{"selected" => path},
      unresolved: ["unresolved #{pass}"],
      omissions: ["omitted #{pass}"],
      observed_at: DateTime.utc_now()
    }
  end
end

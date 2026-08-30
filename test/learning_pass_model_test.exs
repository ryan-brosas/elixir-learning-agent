defmodule LearningPassModelTest do
  use LearningAgent.DataCase, async: false

  alias LearningAgent.{LearningPass, Notes, RepositoryContext, RunContext}

  setup do
    work =
      Path.join(
        System.tmp_dir!(),
        "la_pass_model_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    src = Path.join(work, "src")
    skills = Path.join(work, "skills")
    File.mkdir_p!(src)

    File.write!(
      Path.join(src, "router.ex"),
      "defmodule Router do\\n  def call(_), do: :ok\\nend\\n"
    )

    prev = %{
      skills: Application.get_env(:learning_agent, :skills_root),
      source: Application.get_env(:learning_agent, :source_root),
      max: Application.get_env(:learning_agent, :max_auto_passes),
      model: Application.get_env(:learning_agent, :model),
      complete: Application.get_env(:learning_agent, :note_complete)
    }

    Application.put_env(:learning_agent, :skills_root, skills)
    Application.put_env(:learning_agent, :source_root, src)
    Application.put_env(:learning_agent, :max_auto_passes, 1)

    Application.put_env(:learning_agent, :model,
      enabled: true,
      base_url: "http://stub.local/v1",
      model: "stub-model",
      api_key: nil,
      timeout_ms: 1_000
    )

    on_exit(fn ->
      File.rm_rf!(work)
      restore(:skills_root, prev.skills)
      restore(:source_root, prev.source)
      restore(:max_auto_passes, prev.max)
      restore(:model, prev.model)
      restore(:note_complete, prev.complete)
    end)

    %{src: src, work: work}
  end

  test "a pass feeds the prior note as memory and publishes the model-grown note", %{
    src: src,
    work: work
  } do
    {:ok, repo} = register(src)
    {:ok, pin} = RepositoryContext.add_pin(repo.id, %{root: src, branch: "main"})

    # Seed memory: a published prior note from an earlier pass (pass numbering
    # must advance through the real queue path).
    {:ok, prior_run} = RepositoryContext.queue_pass(repo.id, %{root: src, branch: "main"})
    {:ok, prior_claimed, _} = RunContext.claim(prior_run)

    {:ok, prior_note} =
      Notes.create(prior_claimed.id, repo.id, prior_note_body(src))

    {:ok, _} = Notes.publish(prior_note, Path.join(work, "notes"))

    {:ok, _} =
      LearningAgent.LeaseContext.release_for(
        repo.id,
        prior_claimed.lease_epoch,
        RunContext.holder(),
        "completed"
      )

    {:ok, next} = RepositoryContext.queue_pass(repo.id)
    {:ok, claimed, _} = RunContext.claim(next)

    test_pid = self()

    Application.put_env(:learning_agent, :note_complete, fn payload ->
      send(test_pid, {:learn_payload, payload})

      {:ok,
       %{
         text: """
         # architecture
         Router dispatches every request through one call/1 clause; a single funnel seam.
         Prior structure retained from earlier passes.

         # covered
         - `router.ex`

         # partial/uncited
         - none

         # porter-questions
         How does the funnel map to Plug.Router over an adapter?\nWhat is the smallest call/1 seam to port first?

         # selected-subsystem
         router.ex
         """,
         tool_calls: [],
         usage: %{},
         stop_reason: "stop"
       }}
    end)

    assert {:ok, result} = LearningPass.execute(claimed, "stub-model")

    assert_received {:learn_payload, payload}
    assert payload.model == "stub-model"
    prompt = hd(payload.messages).content |> hd() |> Map.fetch!(:text)
    assert prompt =~ "Memory from previous passes"
    assert prompt =~ "pass 2"
    assert prompt =~ "router.ex"

    published = File.read!(result.note)
    assert published =~ "single funnel seam"
    assert published =~ "- `router.ex`"
    assert published =~ "pass 2."
  end

  test "a failing model call falls back to the deterministic note and still completes", %{
    src: src
  } do
    Application.put_env(:learning_agent, :note_complete, fn _payload ->
      {:error, %{class: :timeout}}
    end)

    {:ok, repo} = register(src)
    {:ok, next} = RepositoryContext.queue_pass(repo.id)
    {:ok, claimed, _} = RunContext.claim(next)

    assert {:ok, result} = LearningPass.execute(claimed, "stub-model")
    assert result.run.state == "completed"
    assert File.read!(result.note) =~ "- `router.ex`"
  end

  defp register(src) do
    RepositoryContext.register(%{
      slug: "modeled",
      display_name: "Modeled",
      graph_project: "modeled",
      source_locator: src
    })
  end

  defp prior_note_body(src) do
    """
    # architecture
    Repository `modeled` at `#{src}` (graph `modeled`), pass 1.
    Baseline layout captured.

    # covered
    - `lib/`

    # partial/uncited
    - `router.ex`

    # porter-questions
    Where does dispatch funnel through?

    # selected-subsystem
    lib/
    """
  end

  defp restore(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore(key, value), do: Application.put_env(:learning_agent, key, value)
end

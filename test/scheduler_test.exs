defmodule LearningAgent.SchedulerTest do
  use LearningAgent.DataCase, async: false

  alias LearningAgent.{RepositoryContext, Run, RunContext, Scheduler}

  import Ecto.Query

  setup do
    previous = Application.get_env(:learning_agent, :worker_slots)
    Application.put_env(:learning_agent, :worker_slots, 1)

    on_exit(fn ->
      Application.put_env(:learning_agent, :worker_slots, previous || 1)
    end)

    :ok
  end

  test "set_concurrency updates the live scheduler cap" do
    pid = start_supervised!(Scheduler)
    assert Scheduler.concurrency() == 1
    assert {:ok, 3} = Scheduler.set_concurrency(3)
    assert Scheduler.concurrency() == 3
    assert Application.get_env(:learning_agent, :worker_slots) == 3
    assert Process.alive?(pid)
    assert {:ok, 40} = Scheduler.set_concurrency(40)
    assert Scheduler.concurrency() == 40
    assert {:error, :worker_slots_invalid} = Scheduler.set_concurrency(99)
  end

  test "self-heal requeues a stranded active repository" do
    src = Path.join(System.tmp_dir!(), "la_selfheal_#{System.unique_integer([:positive])}")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "mod.ex"), "defmodule Sample do\nend\n")

    contain_learning_roots(src)

    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "stranded",
        display_name: "Stranded",
        source_locator: src,
        graph_project: "stranded"
      })

    pid = start_supervised!(Scheduler)
    Scheduler.tick()

    # The same tick may also claim the run, so accept queued or beyond.
    assert_eventually(fn -> repo_run_states(repo.id) != [] end)
    assert Process.alive?(pid)
  end

  test "self-heal respects the failed-run cooldown" do
    src = Path.join(System.tmp_dir!(), "la_cooldown_#{System.unique_integer([:positive])}")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "mod.ex"), "defmodule Sample do\nend\n")
    on_exit(fn -> File.rm_rf(src) end)

    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "cooldown",
        display_name: "Cooldown",
        source_locator: src,
        graph_project: "cooldown"
      })

    {:ok, pin} = RepositoryContext.add_pin(repo.id, %{root: src, branch: "main"})
    {:ok, run} = RunContext.create(repo.id, pin.id, 1)

    # queued->failed is not a state-machine transition; force the terminal row
    # the way a real failed run would leave it.
    from(r in Run, where: r.id == ^run.id)
    |> Repo.update_all(set: [state: "failed", updated_at: DateTime.utc_now()])

    # RunContext.create does not advance the counter; queue_pass would collide
    # on the (repository, pass_number) unique index otherwise.
    from(rp in LearningAgent.Repository, where: rp.id == ^repo.id)
    |> Repo.update_all(set: [next_pass_number: 2])

    pid = start_supervised!(Scheduler)
    Scheduler.tick()
    refute_eventually(fn -> repo_run_states(repo.id) != ["failed"] end)

    backdated = DateTime.add(DateTime.utc_now(), -120, :second)

    from(r in Run, where: r.id == ^run.id)
    |> Repo.update_all(set: [updated_at: backdated])

    Scheduler.tick()
    assert_eventually(fn -> length(repo_run_states(repo.id)) >= 2 end)
    assert Process.alive?(pid)
  end

  # Keep any claimed worker's writes inside tmp, like the pass tests do.
  defp contain_learning_roots(src) do
    skills = Path.join(System.tmp_dir!(), "la_skills_#{System.unique_integer([:positive])}")
    File.mkdir_p!(skills)

    previous_root = Application.get_env(:learning_agent, :skills_root)
    previous_source = Application.get_env(:learning_agent, :source_root)
    previous_max = Application.get_env(:learning_agent, :max_auto_passes)

    Application.put_env(:learning_agent, :skills_root, skills)
    Application.put_env(:learning_agent, :source_root, src)
    Application.put_env(:learning_agent, :max_auto_passes, 1)

    on_exit(fn ->
      File.rm_rf(skills)

      if is_nil(previous_root),
        do: Application.delete_env(:learning_agent, :skills_root),
        else: Application.put_env(:learning_agent, :skills_root, previous_root)

      if is_nil(previous_source),
        do: Application.delete_env(:learning_agent, :source_root),
        else: Application.put_env(:learning_agent, :source_root, previous_source)

      if is_nil(previous_max),
        do: Application.delete_env(:learning_agent, :max_auto_passes),
        else: Application.put_env(:learning_agent, :max_auto_passes, previous_max)
    end)
  end

  defp repo_run_states(repo_id) do
    from(r in Run, where: r.repository_id == ^repo_id, order_by: r.inserted_at)
    |> Repo.all()
    |> Enum.map(& &1.state)
  end

  defp assert_eventually(check, tries \\ 50) do
    if check.() do
      :ok
    else
      if tries <= 0, do: flunk("condition not met"), else: Process.sleep(20)
      assert_eventually(check, tries - 1)
    end
  end

  defp refute_eventually(check, tries \\ 15) do
    if check.() do
      flunk("unexpectedly met")
    else
      if tries > 0 do
        Process.sleep(20)
        refute_eventually(check, tries - 1)
      end
    end
  end
end

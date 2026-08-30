defmodule LearningAgent.GraphCatalogTest do
  use LearningAgent.DataCase, async: false
  alias LearningAgent.{GraphCatalog, RunContext}

  setup do
    previous = Application.get_env(:learning_agent, :memory_projects)

    Application.put_env(:learning_agent, :memory_projects, [
      %{"name" => "demo-graph", "root_path" => "/sources/demo-graph"}
    ])

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :memory_projects),
        else: Application.put_env(:learning_agent, :memory_projects, previous)
    end)

    :ok
  end

  test "start queues one run for a Codebase Memory graph and stop cancels it" do
    assert {:ok, started} = GraphCatalog.start("demo-graph")
    assert started.started
    assert started.repository.graph_project == "demo-graph"
    assert RunContext.active_for(started.repository.id).state == "queued"

    listed = GraphCatalog.list()
    assert listed.worker_slots == 1
    assert Enum.any?(listed.graphs, &(&1.name == "demo-graph" and &1.learning == "queued"))

    assert {:ok, stopped} = GraphCatalog.stop("demo-graph")
    assert stopped.repository.status == "disabled"
    assert hd(stopped.cancelled).cancel_requested
  end

  test "start_all queues every Codebase Memory graph" do
    assert {:ok, fleet} = GraphCatalog.start_all()
    assert fleet.queued >= 1
    assert fleet.graphs >= 1
  end

  test "start_all falls back to registered repositories when memory is offline" do
    Application.put_env(:learning_agent, :memory_projects, [])

    src = Path.join(System.tmp_dir!(), "la_offline_#{System.unique_integer([:positive])}")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "mod.ex"), "defmodule Sample do\nend\n")
    on_exit(fn -> File.rm_rf(src) end)

    {:ok, repo} =
      LearningAgent.RepositoryContext.register(%{
        slug: "offline-fallback",
        display_name: "Offline Fallback",
        source_locator: src,
        graph_project: "offline-fallback"
      })

    assert {:ok, fleet} = GraphCatalog.start_all()
    assert fleet.queued >= 1
    assert fleet.graphs >= 1
    assert RunContext.active_for(repo.id).state == "queued"
  end

  test "start_all reports drained graphs instead of silently queueing nothing" do
    assert {:ok, fleet} = GraphCatalog.start_all()
    assert is_integer(fleet.drained)
    assert fleet.queued + fleet.already_running + fleet.drained + fleet.errors == fleet.graphs
  end

  test "relearn_all re-opens a completed repository and queues a fresh pass" do
    assert {:ok, started} = GraphCatalog.start("demo-graph")
    assert started.started
    # Squeeze the repo the way a drained fleet looks before re-learning.
    {:ok, _} = LearningAgent.RepositoryContext.set_status(started.repository.id, "complete")

    assert {:ok, fleet} = GraphCatalog.relearn_all()
    assert fleet.queued >= 1
    assert RunContext.active_for(started.repository.id).state == "queued"
  end

  test "relearn_all recovers a stopped (disabled) repository" do
    assert {:ok, started} = GraphCatalog.start("demo-graph")
    assert started.started

    # Stop disables the repository even when no run is in flight.
    assert {:ok, _} = GraphCatalog.stop("demo-graph")

    assert {:ok, fleet} = GraphCatalog.relearn_all()
    assert fleet.queued >= 1
    assert RunContext.active_for(started.repository.id).state == "queued"
  end

  test "start works for a registered repository when memory is offline" do
    Application.put_env(:learning_agent, :memory_projects, [])

    src = Path.join(System.tmp_dir!(), "la_offline2_#{System.unique_integer([:positive])}")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "mod.ex"), "defmodule Sample do\nend\n")
    on_exit(fn -> File.rm_rf(src) end)

    {:ok, repo} =
      LearningAgent.RepositoryContext.register(%{
        slug: "offline-single",
        display_name: "Offline Single",
        source_locator: src,
        graph_project: "offline-single"
      })

    assert {:ok, started} = GraphCatalog.start("offline-single")
    assert started.started
    assert RunContext.active_for(repo.id).state == "queued"
  end
end

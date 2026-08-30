defmodule LearningAgent.OpenViking.RelayerTest do
  use LearningAgent.DataCase, async: false
  alias LearningAgent.{OutboxContext, RepositoryContext, RunContext}
  alias LearningAgent.OpenViking.Relayer

  test "drain_once delivers pending outbox events through an injected client" do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "ov1",
        display_name: "ov1",
        graph_project: "ov1",
        source_locator: "/sources/ov1"
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/ov1",
        branch: "main",
        commit_sha: "abc"
      })

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: repo.id,
        run_id: run.id,
        idempotency_key: "ov-test-1",
        event_type: "add_learning_note",
        destination: "learning/ov1",
        payload: %{"path" => "/tmp/note.md"}
      })

    previous = Application.get_env(:learning_agent, :open_viking_client)

    Application.put_env(:learning_agent, :open_viking_client, %{
      add: fn dest, _kw -> {:ok, "ov://" <> dest} end,
      find: fn _q, _ -> {:ok, []} end
    })

    try do
      assert {:ok, _} = Relayer.drain_once()
      assert OutboxContext.backlog() == 0
    after
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :open_viking_client),
        else: Application.put_env(:learning_agent, :open_viking_client, previous)
    end
  end

  test "drain_once respects an explicit batch limit" do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "ov2",
        display_name: "ov2",
        graph_project: "ov2",
        source_locator: "/sources/ov2"
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/ov2",
        branch: "main",
        commit_sha: "abc"
      })

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)

    for n <- 1..3 do
      {:ok, _} =
        OutboxContext.append(%{
          repository_id: repo.id,
          run_id: run.id,
          idempotency_key: "ov-limit-#{n}",
          event_type: "add_learning_note",
          destination: "learning/ov2",
          payload: %{"path" => "/tmp/note-#{n}.md"}
        })
    end

    previous = Application.get_env(:learning_agent, :open_viking_client)

    Application.put_env(:learning_agent, :open_viking_client, %{
      add: fn dest, _kw -> {:ok, "ov://" <> dest} end,
      find: fn _q, _ -> {:ok, []} end
    })

    try do
      assert {:ok, results} = Relayer.drain_once(2)
      assert length(results) == 2
      assert OutboxContext.backlog() == 1
    after
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :open_viking_client),
        else: Application.put_env(:learning_agent, :open_viking_client, previous)
    end
  end

  test "reclaim_stale returns stranded claimed and retry_wait events to pending" do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "ov3",
        display_name: "ov3",
        graph_project: "ov3",
        source_locator: "/sources/ov3"
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/ov3",
        branch: "main",
        commit_sha: "abc"
      })

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)

    {:ok, event} =
      OutboxContext.append(%{
        repository_id: repo.id,
        run_id: run.id,
        idempotency_key: "ov-stale-1",
        event_type: "add_learning_note",
        destination: "learning/ov3",
        payload: %{"path" => "/tmp/note.md"}
      })

    future = DateTime.add(DateTime.utc_now(), 60, :second)
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    # A claim from a dead publisher older than the cutoff is stranded: only
    # reclaim_stale can return it to pending.
    claimed = OutboxContext.claim_pending(1, "dead-publisher")
    assert hd(claimed).id == event.id

    assert 1 = OutboxContext.reclaim_stale(future)
    assert OutboxContext.backlog() == 1

    # Claims newer than the cutoff stay held.
    _ = OutboxContext.claim_pending(1, "live-publisher")
    assert 0 = OutboxContext.reclaim_stale(past)
    assert OutboxContext.backlog() == 0
    assert 1 = OutboxContext.reclaim_stale(future)
  end
end

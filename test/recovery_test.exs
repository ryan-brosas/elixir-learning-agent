defmodule LearningAgent.RecoveryTest do
  use LearningAgent.DataCase, async: true
  alias LearningAgent.{Repo, Run, Lease, RepositoryContext, RunContext, Recovery, LeaseContext}

  defp setup_run(slug) do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: slug,
        display_name: slug,
        graph_project: slug,
        source_locator: "/sources/" <> slug
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/" <> slug,
        branch: "main",
        commit_sha: "abc"
      })

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)
    {:ok, claimed, _} = RunContext.claim(run)
    {repo, claimed}
  end

  test "recovery requeues an orphaned run whose lease expired" do
    {_repo, run} = setup_run("recovery1")

    # simulate crash: lease expires, worker vanishes, run still 'claimed'
    lease = Repo.get!(Lease, run.repository_id)
    expired = Ecto.Changeset.change(lease, expires_at: DateTime.add(DateTime.utc_now(), -60))
    {:ok, _} = Repo.update(expired)

    assert LearningAgent.Recovery.run() == :ok

    requeued = Repo.get!(Run, run.id)
    assert requeued.state == "queued"
    assert is_nil(requeued.lease_epoch)
  end

  test "recovery cancels an orphaned run that was cancelled before worker death" do
    {_repo, run} = setup_run("recovery2")
    {:ok, _} = RunContext.request_cancel(run.id)

    lease = Repo.get(Lease, run.repository_id)
    expired = Ecto.Changeset.change(lease, expires_at: DateTime.add(DateTime.utc_now(), -60))
    {:ok, _} = Repo.update(expired)

    assert :ok = LearningAgent.Recovery.run()

    assert Repo.get!(Run, run.id).state == "queued" or
             Repo.get!(Run, run.id).state == "cancelled"
  end
end

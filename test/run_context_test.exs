defmodule LearningAgent.RunContextTest do
  use LearningAgent.DataCase, async: true
  alias LearningAgent.{Repo, Run, RepositoryContext, RunContext}

  defp run_fixture(slug) do
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
    run
  end

  test "create -> claim transitions to claimed with epoch" do
    run = run_fixture("rc1")
    assert run.state == "queued"
    {:ok, claimed, lease} = RunContext.claim(run)
    assert claimed.state == "claimed"
    assert claimed.lease_epoch == 1
    assert lease.epoch == 1
  end

  test "a second claim is rejected while the lease is live" do
    run = run_fixture("rc2")
    {:ok, _, _} = RunContext.claim(run)
    assert {:error, :still_held} = RunContext.claim(Repo.get!(Run, run.id))
  end

  test "a later run can claim after the previous lease is released" do
    run = run_fixture("rc2b")
    {:ok, claimed, lease} = RunContext.claim(run)

    assert {:ok, _} =
             LearningAgent.LeaseContext.release(
               lease,
               lease.epoch,
               RunContext.holder(),
               "completed"
             )

    queued = claimed |> Ecto.Changeset.change(state: "queued") |> Repo.update!()
    assert {:ok, _, next} = RunContext.claim(queued)
    assert next.epoch == 2
  end

  test "cancel-before-start: a cancelled queued run is never claimed" do
    run = run_fixture("rc3")
    {:ok, _} = RunContext.request_cancel(run.id)
    assert {:error, :cancelled_before_start} = RunContext.claim(Repo.get!(Run, run.id))
  end

  test "epoch fencing: a stale epoch transition fails, correct epoch succeeds" do
    run = run_fixture("rc4")
    {:ok, claimed, _} = RunContext.claim(run)
    assert {:error, :stale_epoch} = RunContext.transition(claimed.id, "claimed", "preflight", 999)
    assert {:ok, _} = RunContext.transition(claimed.id, "claimed", "preflight", 1)
  end

  test "invalid transition is rejected before hitting the DB" do
    run = run_fixture("rc5")
    {:ok, claimed, _} = RunContext.claim(run)

    assert {:error, :invalid_transition} =
             RunContext.transition(claimed.id, "claimed", "completed", 1)
  end

  test "retry_failed_io requeues permission failures" do
    run = run_fixture("rc7")
    {:ok, claimed, _} = RunContext.claim(run)
    {:ok, _} = RunContext.transition(claimed.id, "claimed", "preflight", 1)
    {:ok, drafting} = RunContext.transition(claimed.id, "preflight", "note_drafting", 1)

    {:ok, _} =
      RunContext.transition(drafting.id, "note_drafting", "failed", 1, %{
        failure_class: "not_writable",
        finished_at: DateTime.utc_now()
      })

    assert RunContext.retry_failed_io() >= 1
    assert Repo.get!(Run, run.id).state == "queued"
  end

  test "request_cancel is idempotent (never flips true -> false)" do
    run = run_fixture("rc6")
    {:ok, _} = RunContext.request_cancel(run.id)
    {:ok, again} = RunContext.request_cancel(run.id)
    assert again.cancel_requested
    assert RunContext.cancelled?(again)
  end
end

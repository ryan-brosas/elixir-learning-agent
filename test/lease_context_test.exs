defmodule LearningAgent.LeaseContextTest do
  use LearningAgent.DataCase, async: true
  alias LearningAgent.{Repo, RepositoryContext, LeaseContext, Run}

  defp lease_setup(slug) do
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

    {:ok, run} =
      %Run{}
      |> Run.changeset(%{repository_id: repo.id, pin_id: pin.id, pass_number: 1, state: "queued"})
      |> Repo.insert()

    {repo, run}
  end

  test "claim creates a lease with epoch 1 for a repository" do
    {repo, run} = lease_setup("r1")
    assert {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    assert lease.epoch == 1
    assert lease.holder_id == "holder-a"
  end

  test "a live lease cannot be claimed by a second worker" do
    {repo, run} = lease_setup("r2")
    {:ok, _} = LeaseContext.claim(repo.id, run.id, "holder-a")
    assert {:error, :still_held} = LeaseContext.claim(repo.id, run.id, "holder-b")
  end

  test "stale epoch cannot renew (fencing)" do
    {repo, run} = lease_setup("r3")
    {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    assert {:error, :stale_epoch} = LeaseContext.renew(lease, 99, "holder-a")
    assert {:error, :stale_epoch} = LeaseContext.renew(lease, lease.epoch, "intruder")
  end

  test "expired lease is reclaimed with an incremented epoch (fencing)" do
    {repo, run} = lease_setup("r4")
    {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    expired = lease |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    {:ok, _} = Repo.update(expired)
    assert {:ok, reclaimed} = LeaseContext.claim(repo.id, run.id, "holder-b")
    assert reclaimed.epoch == 2
    assert reclaimed.holder_id == "holder-b"
  end

  test "a released lease can be claimed again" do
    {repo, run} = lease_setup("r6")
    {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    {:ok, _} = LeaseContext.release(lease, lease.epoch, "holder-a", "completed")
    assert {:ok, again} = LeaseContext.claim(repo.id, run.id, "holder-b")
    assert again.epoch == 2
    assert again.holder_id == "holder-b"
    assert is_nil(again.released_at)
  end

  test "claim expiry is minutes, not days" do
    {repo, run} = lease_setup("r7")
    {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    diff = DateTime.diff(lease.expires_at, lease.claimed_at, :second)
    assert diff > 60
    assert diff <= 6 * 60
  end

  test "release only succeeds for current epoch+holder and is idempotent" do
    {repo, run} = lease_setup("r5")
    {:ok, lease} = LeaseContext.claim(repo.id, run.id, "holder-a")
    assert {:ok, released} = LeaseContext.release(lease, lease.epoch, "holder-a", "completed")
    refute is_nil(released.released_at)
    # release is idempotent for the same holder+epoch
    assert {:ok, _} = LeaseContext.release(lease, lease.epoch, "holder-a", "completed")
  end
end

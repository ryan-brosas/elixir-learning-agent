defmodule LearningAgent.RepositoryTest do
  use LearningAgent.DataCase, async: true
  alias LearningAgent.{Repo, Repository, RepositoryPin, RepositoryContext}

  test "register a repository persists a slug, and a duplicate slug is rejected by the DB" do
    assert {:ok, repo} =
             RepositoryContext.register(%{
               slug: "requests",
               display_name: "Requests",
               source_locator: "/sources/requests",
               graph_project: "requests"
             })

    assert repo.slug == "requests"
    assert repo.status == "registered"

    # duplicate slug -> changeset error backed by the DB unique index
    assert {:error, cs} =
             RepositoryContext.register(%{
               slug: "requests",
               display_name: "Another",
               source_locator: "/sources/other",
               graph_project: "requests2"
             })

    assert Keyword.has_key?(cs.errors, :slug)
  end

  test "add a pin and set repository status" do
    {:ok, repo} = repo("requests")

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/requests",
        branch: "main",
        commit_sha: "abc123"
      })

    assert pin.root == "/sources/requests"

    {:ok, repo2} = RepositoryContext.set_status(repo.id, "index_ready")
    assert repo2.status == "index_ready"
  end

  test "a graph generation change creates a new immutable pin" do
    {:ok, repo} = repo("generations")

    attrs = %{
      root: repo.source_locator,
      branch: "main",
      commit_sha: "abc123",
      graph_generation: "generation-1"
    }

    assert {:ok, first_run} = RepositoryContext.queue_pass(repo.id, attrs)

    assert {:ok, second_run} =
             RepositoryContext.queue_pass(repo.id, %{attrs | graph_generation: "generation-2"})

    refute second_run.pin_id == first_run.pin_id
    assert Repo.aggregate(RepositoryPin, :count, :id) == 2
  end

  defp repo(slug) do
    RepositoryContext.register(%{
      slug: slug,
      display_name: slug,
      graph_project: slug,
      source_locator: "/sources/" <> slug
    })
  end
end

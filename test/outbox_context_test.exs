defmodule LearningAgent.OutboxContextTest do
  use LearningAgent.DataCase, async: true
  alias LearningAgent.{Repo, OutboxContext, Repository}

  defp repo_id(slug) do
    {:ok, r} =
      %Repository{}
      |> Repository.changeset(%{
        slug: slug,
        display_name: slug,
        graph_project: slug,
        source_locator: "/sources/" <> slug
      })
      |> Repo.insert()

    r.id
  end

  test "outbox insert with same idempotency_key is rejected twice" do
    rid = repo_id("o1")

    common = %{
      repository_id: rid,
      idempotency_key: "ov:add:viking://resources/pass1:digest1",
      event_type: "add_learning_note",
      payload: %{content_digest: "digest1"}
    }

    assert {:ok, _} = OutboxContext.append(common)
    assert {:error, cs} = OutboxContext.append(common)
    assert Keyword.has_key?(cs.errors, :idempotency_key)
  end

  test "distinct digest keys coexist" do
    rid = repo_id("o2")

    assert {:ok, _} =
             OutboxContext.append(%{repository_id: rid, idempotency_key: "k1", event_type: "a"})

    assert {:ok, _} =
             OutboxContext.append(%{repository_id: rid, idempotency_key: "k2", event_type: "b"})

    assert Repo.aggregate(LearningAgent.OutboxEvent, :count, :id) == 2
  end
end

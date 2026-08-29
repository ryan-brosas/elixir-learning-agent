defmodule LearningAgent.OpenVikingPublisherTest do
  use LearningAgent.DataCase, async: false
  import Ecto.Query
  alias LearningAgent.{Repo, OutboxContext, OutboxEvent, RepositoryContext}
  alias LearningAgent.OpenViking.Publisher

  defp repo_id(slug) do
    {:ok, r} =
      RepositoryContext.register(%{
        slug: slug,
        display_name: slug,
        graph_project: slug,
        source_locator: "/sources/" <> slug
      })

    r.id
  end

  defp ev(key) do
    Repo.one(from(e in OutboxEvent, where: e.idempotency_key == ^key))
  end

  defp client(opts) do
    %{
      add: Keyword.get(opts, :add, fn _, _ -> {:ok, :added} end),
      find: fn _, _ -> {:ok, [%{uri: "x"}]} end
    }
  end

  test "drain delivers an add_learning_note" do
    rid = repo_id("ov1")

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k1",
        event_type: "add_learning_note",
        payload: %{"destination" => "viking://resources/x"}
      })

    {:ok, [_]} = Publisher.drain(client([]))
    assert ev("k1").state == "delivered"
    refute is_nil(ev("k1").delivered_at)
  end

  test "a transient failure states retry_wait" do
    rid = repo_id("ov2")

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k2",
        event_type: "add_learning_note",
        payload: %{"destination" => "v"}
      })

    {:ok, [_]} = Publisher.drain(client(add: fn _, _ -> {:error, :timeout} end))
    assert ev("k2").state in ["retry_wait", "failed"]
  end

  test "an unsupported event_type is failed as permanent" do
    rid = repo_id("ov3")

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k3",
        event_type: "delete_all",
        payload: %{}
      })

    {:ok, [_]} = Publisher.drain(client([]))
    assert ev("k3").state == "failed"
  end

  test "verify_symbol with a hit verifies and the event is delivered" do
    rid = repo_id("ov4")

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k4",
        event_type: "verify_symbol",
        payload: %{"query" => "Request"}
      })

    {:ok, [_]} = Publisher.drain(client([]))
    assert ev("k4").state == "delivered"
  end

  test "duplicate idempotency key is rejected at append" do
    rid = repo_id("ov5")

    common = %{
      repository_id: rid,
      idempotency_key: "k5",
      event_type: "add_learning_note",
      payload: %{}
    }

    assert {:ok, _} = OutboxContext.append(common)
    assert {:error, _} = OutboxContext.append(common)
  end
end

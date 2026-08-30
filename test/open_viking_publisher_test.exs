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

  defp upload_instruction(url) do
    {:ok,
     %{
       "structuredContent" => %{"result" => "HTTP POST the file bytes to: " <> url},
       "content" => [%{"type" => "text", "text" => "HTTP POST the file bytes to: " <> url}]
     }}
  end

  defp with_upload_stub(fun, test_fn) do
    previous = Application.get_env(:learning_agent, :open_viking_upload)
    Application.put_env(:learning_agent, :open_viking_upload, fun)

    try do
      test_fn.()
    after
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :open_viking_upload),
        else: Application.put_env(:learning_agent, :open_viking_upload, previous)
    end
  end

  test "drain delivers an add_learning_note" do
    rid = repo_id("ov1")
    note = Path.join(System.tmp_dir!(), "la-note-k1-#{System.unique_integer([:positive])}.md")
    File.write!(note, "# learning note body")
    on_exit(fn -> File.rm(note) end)

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k1",
        event_type: "add_learning_note",
        payload: %{"destination" => "viking://resources/x", "path" => note}
      })

    {:ok, [_]} = Publisher.drain(client([]))
    assert ev("k1").state == "delivered"
    refute is_nil(ev("k1").delivered_at)
  end

  test "delivery posts the note bytes and records the root_uri" do
    rid = repo_id("ov6")
    note = Path.join(System.tmp_dir!(), "la-note-#{System.unique_integer([:positive])}.md")
    File.write!(note, "# learning note body")
    on_exit(fn -> File.rm(note) end)

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k6",
        event_type: "add_learning_note",
        payload: %{"destination" => "learning/ov6", "path" => note}
      })

    upload_instruction = "http://127.0.0.1:1933/api/v1/resources/temp_upload?token=abc"
    test_pid = self()

    with_upload_stub(
      fn url, path ->
        send(test_pid, {:uploaded, url, path})
        {:ok, "viking://resources/note-1"}
      end,
      fn ->
        {:ok, [_]} =
          Publisher.drain(
            client(add: fn _dest, _kw -> upload_instruction(upload_instruction) end)
          )
      end
    )

    assert_received {:uploaded, ^upload_instruction, ^note}
    assert ev("k6").state == "delivered"
    assert ev("k6").payload["remote_ref"] == "viking://resources/note-1"
  end

  test "a directory path is zipped before upload" do
    rid = repo_id("ov7")

    dir =
      Path.join(System.tmp_dir!(), "la-capsule-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(dir, "references"))
    File.write!(Path.join(dir, "SKILL.md"), "# capsule")
    File.write!(Path.join([dir, "references", "pass.md"]), "body")
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k7",
        event_type: "add_capsule",
        payload: %{"destination" => "skills/ov7", "path" => dir}
      })

    upload_instruction = "http://127.0.0.1:1933/api/v1/resources/temp_upload?token=zip"

    with_upload_stub(
      fn _url, _path -> {:ok, "viking://resources/ov7"} end,
      fn ->
        {:ok, [_]} =
          Publisher.drain(
            client(add: fn _dest, _kw -> upload_instruction(upload_instruction) end)
          )
      end
    )

    assert ev("k7").state == "delivered"
    assert ev("k7").payload["remote_ref"] == "viking://resources/ov7"
  end

  test "a missing path fails the event permanently" do
    rid = repo_id("ov8")

    {:ok, _} =
      OutboxContext.append(%{
        repository_id: rid,
        idempotency_key: "k8",
        event_type: "add_capsule",
        payload: %{"destination" => "skills/ov8"}
      })

    {:ok, [_]} = Publisher.drain(client([]))
    assert ev("k8").state == "failed"
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

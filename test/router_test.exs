defmodule LearningAgentWeb.RouterTest do
  use LearningAgent.DataCase, async: false
  import Plug.Conn
  import Plug.Test
  alias LearningAgentWeb.Router

  defp call(method, path, token \\ nil) do
    Router.call(conn(method, path) |> put_auth(token), Router.init([]))
  end

  defp call_json(method, path, token, body) do
    Plug.Test.conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_auth(token)
    |> Router.call(Router.init([]))
  end

  defp put_auth(conn, nil), do: conn
  defp put_auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp with_local_dogfood(fun) do
    previous = System.get_env("LA_LOCAL_DOGFOOD")
    System.put_env("LA_LOCAL_DOGFOOD", "true")

    try do
      fun.()
    after
      if is_nil(previous),
        do: System.delete_env("LA_LOCAL_DOGFOOD"),
        else: System.put_env("LA_LOCAL_DOGFOOD", previous)
    end
  end

  defp with_model_config(config, fun) do
    previous = Application.get_env(:learning_agent, :model)
    Application.put_env(:learning_agent, :model, config)

    try do
      fun.()
    after
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :model),
        else: Application.put_env(:learning_agent, :model, previous)
    end
  end

  test "health/live is open and reports live" do
    assert call("GET", "/health/live").status == 200
  end

  test "health/ready requires the DB and reports ready" do
    assert call("GET", "/health/ready").status == 200
  end

  test "/v1/repositories without a token is 401" do
    assert call("GET", "/v1/repositories").status == 401
  end

  test "/v1/repositories with a viewer token is 200" do
    LearningAgent.RepositoryContext.register(%{
      slug: "api1",
      display_name: "api1",
      graph_project: "api1",
      source_locator: "/sources/api1"
    })

    conn = call("GET", "/v1/repositories", "view-token")
    assert conn.status == 200
    assert conn.resp_body =~ "api1"
  end

  test "a viewer cannot run an administrator action" do
    conn = call("POST", "/v1/runs/00000000-0000-0000-0000-000000000001/cancel", "view-token")
    assert conn.status in [401, 403, 404]
  end

  test "the root renders the model playground with security headers" do
    response = call("GET", "/")
    assert response.status == 200
    assert response.resp_body =~ "Model playground"
    assert response.resp_body =~ "Save in this browser"
    assert response.resp_body =~ "#overview"
    assert response.resp_body =~ "#graphs"
    assert response.resp_body =~ "Start learning"
    assert response.resp_body =~ "/v1/graphs/start-all"
    refute response.resp_body =~ "startGraph("
    assert response.resp_body =~ "#runs"
    assert response.resp_body =~ "#settings"
    assert response.resp_body =~ ~s(id="worker-slots")
    assert response.resp_body =~ ~s(id="refresh-lanes")
    assert response.resp_body =~ ~s(id="lanes")
    assert response.resp_body =~ "/v1/settings"
    assert response.resp_body =~ "/v1/overview"
    assert response.resp_body =~ "/v1/graphs/"
    assert response.resp_body =~ "Re-learn all"
    assert response.resp_body =~ "/v1/graphs/relearn-all"
    assert response.resp_body =~ "[hidden] { display: none !important; }"
    assert response.resp_body =~ ~s(data-view="graphs" hidden)
    refute response.resp_body =~ ~s(id="repo-slug")
    refute response.resp_body =~ "Add a source"
    assert response.resp_body =~ ~s(id="base-url")
    assert response.resp_body =~ ~s(id="connection-ready")
    assert response.resp_body =~ ~s(id="using-line")
    refute response.resp_body =~ ">Configured</dt>"
    assert response.resp_body =~ ~s(id="api-key")
    assert response.resp_body =~ ~s(<select id="model")
    assert response.resp_body =~ ~s(id="model-list")
    assert response.resp_body =~ "picker-option"
    assert response.resp_body =~ "background: #1b1a17"
    assert response.resp_body =~ "color: #ece7dc"
    assert response.resp_body =~ "color: #12110f"
    assert response.resp_body =~ "/v1/models/list"
    assert response.resp_body =~ "localStorage"
    assert response.resp_body =~ "applyCatalog"
    assert response.resp_body =~ "persistConnection"
    assert response.resp_body =~ "ensureModels"
    assert response.resp_body =~ "--paper:"
    assert response.resp_body =~ "ui-serif"
    refute response.resp_body =~ "Bearer token"
    refute response.resp_body =~ "#38bdf8"
    refute response.resp_body =~ "radial-gradient"
    refute response.resp_body =~ "text-transform: uppercase"
    assert Plug.Conn.get_resp_header(response, "content-security-policy") != []
    assert Plug.Conn.get_resp_header(response, "x-content-type-options") == ["nosniff"]
  end

  test "model catalog requires viewer authorization and never returns the API key" do
    assert call("GET", "/v1/models").status == 401

    with_model_config(
      %{base_url: "http://model.test/v1", model: "fixture-model", api_key: "do-not-return"},
      fn ->
        response = call("GET", "/v1/models", "view-token")
        assert response.status == 200
        assert response.resp_body =~ "fixture-model"
        assert response.resp_body =~ "api_key_configured"
        refute response.resp_body =~ "do-not-return"
      end
    )
  end

  test "operator can run a normalized model completion through the API" do
    test_pid = self()

    transport = fn body ->
      send(test_pid, {:model_request, body})

      {:ok,
       %{
         "choices" => [
           %{
             "message" => %{"content" => "connected", "tool_calls" => []},
             "finish_reason" => "stop"
           }
         ],
         "usage" => %{"prompt_tokens" => 7, "completion_tokens" => 2}
       }}
    end

    with_model_config(
      %{base_url: "http://model.test/v1", model: "fixture-model", transport: transport},
      fn ->
        response = call_json("POST", "/v1/models/test", "op-token", %{"prompt" => "hello"})
        assert response.status == 200

        assert Jason.decode!(response.resp_body) == %{
                 "model" => "fixture-model",
                 "text" => "connected",
                 "usage" => %{"prompt_tokens" => 7, "completion_tokens" => 2},
                 "stop_reason" => "stop"
               }

        assert_receive {:model_request, %{"model" => "fixture-model", "messages" => messages}}
        assert Enum.at(messages, 1)["content"] == "hello"
      end
    )
  end

  test "model list requires operator authorization in protected mode" do
    assert call_json("POST", "/v1/models/list", nil, %{"base_url" => "http://model.test/v1"}).status ==
             401
  end

  test "model list accepts browser connection settings in local dogfood mode" do
    with_local_dogfood(fn ->
      with_model_config(
        %{
          base_url: nil,
          model: nil,
          list_transport: fn ->
            {:ok, %{"data" => [%{"id" => "gpt-4o-mini"}, %{"id" => "gpt-4.1"}]}}
          end
        },
        fn ->
          response =
            call_json("POST", "/v1/models/list", nil, %{
              "base_url" => "http://model.test/v1",
              "api_key" => "browser-only-key"
            })

          assert response.status == 200

          assert Jason.decode!(response.resp_body) == %{
                   "endpoint" => "http://model.test/v1",
                   "models" => ["gpt-4o-mini", "gpt-4.1"]
                 }
        end
      )
    end)
  end

  test "model test requires operator authorization and rejects unknown fields" do
    assert call_json("POST", "/v1/models/test", "view-token", %{"prompt" => "hello"}).status ==
             403

    response =
      call_json("POST", "/v1/models/test", "op-token", %{"prompt" => "hello", "extra" => true})

    assert response.status == 422
    assert response.resp_body =~ "unknown request fields"
  end

  test "operator can supply an ephemeral model URL, key, and model" do
    test_pid = self()

    transport = fn body ->
      send(test_pid, {:ephemeral_model_request, body})
      {:ok, %{"choices" => [%{"message" => %{"content" => "ephemeral", "tool_calls" => []}}]}}
    end

    with_model_config(%{base_url: nil, model: nil, transport: transport}, fn ->
      response =
        call_json("POST", "/v1/models/test", "op-token", %{
          "prompt" => "hello",
          "model" => "fixture-model",
          "base_url" => "http://model.test/v1",
          "api_key" => "browser-only-key"
        })

      assert response.status == 200
      assert Jason.decode!(response.resp_body)["text"] == "ephemeral"
      refute response.resp_body =~ "browser-only-key"
      assert_receive {:ephemeral_model_request, request}
      refute Map.has_key?(request, "api_key")
    end)
  end

  test "model test rejects an invalid ephemeral URL" do
    response =
      call_json("POST", "/v1/models/test", "op-token", %{
        "prompt" => "hello",
        "model" => "fixture-model",
        "base_url" => "file:///tmp/model"
      })

    assert response.status == 422
    assert response.resp_body =~ "OpenAI-compatible URL is invalid"
  end

  test "local dogfood model test needs no bearer token" do
    with_local_dogfood(fn ->
      with_model_config(
        %{
          base_url: "http://model.test/v1",
          model: "fixture-model",
          transport: fn _body ->
            {:ok, %{"choices" => [%{"message" => %{"content" => "local"}}]}}
          end
        },
        fn ->
          response =
            call_json("POST", "/v1/models/test", nil, %{
              "prompt" => "hello",
              "model" => "fixture-model",
              "base_url" => "http://model.test/v1",
              "api_key" => "browser-only-key"
            })

          assert response.status == 200
          assert Jason.decode!(response.resp_body)["text"] == "local"
        end
      )
    end)
  end

  test "local dogfood overview lists repositories and queued runs" do
    with_local_dogfood(fn ->
      {:ok, repo} =
        LearningAgent.RepositoryContext.register(%{
          slug: "learn1",
          display_name: "Learn One",
          graph_project: "learn1",
          source_locator: "/sources/learn1"
        })

      {:ok, run} = LearningAgent.RepositoryContext.queue_pass(repo.id)
      response = call("GET", "/v1/overview")
      body = Jason.decode!(response.resp_body)

      assert response.status == 200
      assert body["repository_count"] >= 1
      assert Enum.any?(body["repositories"], &(&1["slug"] == "learn1"))
      assert Enum.any?(body["runs"], &(&1["id"] == run.id))
      assert body["run_counts"]["queued"] >= 1
    end)
  end

  test "local dogfood can change worker slots without restart" do
    previous = Application.get_env(:learning_agent, :worker_slots)
    previous_lanes = Application.get_env(:learning_agent, :worker_lanes)
    Application.put_env(:learning_agent, :worker_slots, 1)
    Application.put_env(:learning_agent, :worker_lanes, nil)

    try do
      with_local_dogfood(fn ->
        listed = call("GET", "/v1/settings")
        assert listed.status == 200
        assert Jason.decode!(listed.resp_body)["worker_slots"] == 1

        updated =
          call_json("PUT", "/v1/settings", nil, %{worker_slots: 4})

        assert updated.status == 200
        assert Jason.decode!(updated.resp_body)["worker_slots"] == 4
        assert LearningAgent.RuntimeSettings.worker_slots() == 4

        split =
          call_json("PUT", "/v1/settings", nil, %{
            lanes: [
              %{model: "ds-pro", slots: 20},
              %{model: "glm-5.3-flash", slots: 20}
            ]
          })

        assert split.status == 200
        body = Jason.decode!(split.resp_body)
        assert body["worker_slots"] == 40
        assert Enum.map(body["lanes"], & &1["model"]) == ["ds-pro", "glm-5.3-flash"]

        rejected = call_json("PUT", "/v1/settings", nil, %{worker_slots: 99})
        assert rejected.status == 422
      end)
    after
      Application.put_env(:learning_agent, :worker_slots, previous || 1)

      if previous_lanes,
        do: Application.put_env(:learning_agent, :worker_lanes, previous_lanes),
        else: Application.delete_env(:learning_agent, :worker_lanes)
    end
  end

  test "local dogfood can start and stop a Codebase Memory graph" do
    previous = Application.get_env(:learning_agent, :memory_projects)

    Application.put_env(:learning_agent, :memory_projects, [
      %{"name" => "requests", "root_path" => "/sources/requests"}
    ])

    try do
      with_local_dogfood(fn ->
        start = call("POST", "/v1/graphs/requests/start")
        assert start.status == 200
        body = Jason.decode!(start.resp_body)
        assert body["started"] == true
        assert body["repository"]["graph_project"] == "requests"

        stop = call("POST", "/v1/graphs/requests/stop")
        assert stop.status == 200
        assert Jason.decode!(stop.resp_body)["repository"]["status"] == "disabled"

        fleet = call("POST", "/v1/graphs/start-all")
        assert fleet.status == 200
        assert Jason.decode!(fleet.resp_body)["queued"] >= 1
      end)
    after
      if is_nil(previous),
        do: Application.delete_env(:learning_agent, :memory_projects),
        else: Application.put_env(:learning_agent, :memory_projects, previous)
    end
  end

  test "local dogfood can register a repository through the API" do
    with_local_dogfood(fn ->
      response =
        call_json("POST", "/v1/repositories", nil, %{
          "slug" => "learn2",
          "display_name" => "Learn Two",
          "source_locator" => "/sources/learn2",
          "graph_project" => "learn2"
        })

      assert response.status == 201
      assert Jason.decode!(response.resp_body)["repository"]["slug"] == "learn2"
    end)
  end

  test "model test enforces the prompt byte limit" do
    prompt = String.duplicate("x", 16_385)
    response = call_json("POST", "/v1/models/test", "op-token", %{"prompt" => prompt})

    assert response.status == 422
    assert response.resp_body =~ "16 KiB"
  end

  test "model test reports an explicit unavailable configuration" do
    with_model_config(%{base_url: nil, model: nil}, fn ->
      response = call_json("POST", "/v1/models/test", "op-token", %{"prompt" => "hello"})
      assert response.status == 503
      assert response.resp_body =~ "model endpoint is not configured"
    end)
  end
end

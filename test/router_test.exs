defmodule LearningAgentWeb.RouterTest do
  use LearningAgent.DataCase, async: false
  use Plug.Test
  alias LearningAgentWeb.Router

  defp call(method, path, token \\ nil) do
    Router.call(conn(method, path) |> put_auth(token), Router.init([]))
  end

  defp put_auth(conn, nil), do: conn
  defp put_auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

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
end

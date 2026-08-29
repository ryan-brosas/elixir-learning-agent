defmodule LearningAgentWeb.Router do
  @moduledoc """
  Operator + health API (docs/04 §12-§13). JSON only; never exposes arbitrary tool
  execution. health/live and health/ready are unauthenticated; /v1/* requires a role.
  """
  use Plug.Router
  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  alias LearningAgent.{Repo, Run, RunContext, OutboxContext, Operator}

  get "/health/live" do
    send_json(conn, 200, %{status: "live"})
  end

  get "/health/ready" do
    if db_ready?() do
      send_json(conn, 200, %{status: "ready"})
    else
      send_json(conn, 503, %{status: "not_ready", reason: :database})
    end
  end

  get "/v1/repositories" do
    with_authorize(conn, :viewer, fn _auth ->
      send_json(conn, 200, %{
        repositories: Enum.map(LearningAgent.RepositoryContext.all(), &surface_repo/1)
      })
    end)
  end

  post "/v1/runs/:id/cancel" do
    with_authorize(conn, :operator, fn _auth ->
      case RunContext.request_cancel(id) do
        {:ok, run} ->
          send_json(conn, 200, %{run: id, state: run.state, cancelled: run.cancel_requested})

        {:error, _} ->
          send_json(conn, 404, %{error: :not_found})
      end
    end)
  end

  post "/v1/runs/:id/resolve-blocker" do
    with_authorize(conn, :operator, fn _auth ->
      case Repo.get(Run, id) do
        nil ->
          send_json(conn, 404, %{error: :not_found})

        run ->
          {:ok, _} = RunContext.unfenced_transition(run.id, run.state, "queued")
          send_json(conn, 200, %{run: id, state: "queued"})
      end
    end)
  end

  post "/v1/outbox/:id/retry" do
    with_authorize(conn, :administrator, fn _auth ->
      OutboxContext.retry!(id)
      send_json(conn, 200, %{retried: id})
    end)
  end

  match _ do
    send_json(conn, 404, %{error: :not_found})
  end

  defp with_authorize(conn, role, fun) do
    case Operator.authenticate(conn) do
      {actual_role, _subject} ->
        if Operator.authorize?(role, actual_role) do
          fun.(conn)
        else
          send_json(conn, 403, %{error: :forbidden})
        end

      :invalid ->
        send_json(conn, 401, %{error: :unauthorized})
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp surface_repo(r) do
    %{
      id: r.id,
      slug: r.slug,
      display_name: r.display_name,
      status: r.status,
      graph_project: r.graph_project
    }
  end

  defp db_ready? do
    case Repo.query("SELECT 1") do
      {:ok, _} -> true
      _ -> false
    end
  end
end

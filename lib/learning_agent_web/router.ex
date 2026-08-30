defmodule LearningAgentWeb.Router do
  @moduledoc """
  Operator + health API (docs/04 §12-§13). JSON only; never exposes arbitrary tool
  execution. health/live and health/ready are public; local model dogfood routes may be
  public when explicitly enabled, while the remaining /v1/* routes require a role.
  """
  use Plug.Router
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: 32_768
  )

  plug(:match)
  plug(:dispatch)

  alias LearningAgent.{
    Repo,
    Run,
    RunContext,
    OutboxContext,
    Operator,
    ModelGateway,
    OperatorBoard,
    RepositoryContext,
    GraphCatalog,
    RuntimeSettings
  }

  alias LearningAgentWeb.Frontend

  get "/" do
    conn
    |> security_headers()
    |> Plug.Conn.put_resp_content_type("text/html", "utf-8")
    |> Plug.Conn.send_resp(200, Frontend.page())
  end

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

  get "/v1/models" do
    with_model_access(conn, :viewer, fn _auth ->
      send_json(conn, 200, %{models: [ModelGateway.catalog()]})
    end)
  end

  post "/v1/models/list" do
    with_model_access(conn, :operator, fn _auth ->
      case model_connection_params(conn.body_params) do
        {:ok, connection} ->
          case ModelGateway.available_models(connection) do
            {:ok, response} -> send_json(conn, 200, response)
            {:error, reason} -> model_error(conn, reason)
          end

        {:error, reason} ->
          model_error(conn, %{class: :invalid_request, reason: reason})
      end
    end)
  end

  post "/v1/models/test" do
    with_model_access(conn, :operator, fn _auth ->
      case model_test_params(conn.body_params) do
        {:ok, {prompt, model, connection}} ->
          case ModelGateway.test(prompt, model, connection) do
            {:ok, response} -> send_json(conn, 200, response)
            {:error, reason} -> model_error(conn, reason)
          end

        {:error, reason} ->
          model_error(conn, %{class: :invalid_request, reason: reason})
      end
    end)
  end

  get "/v1/overview" do
    with_model_access(conn, :viewer, fn _auth ->
      send_json(conn, 200, OperatorBoard.snapshot())
    end)
  end

  get "/v1/activity" do
    with_model_access(conn, :viewer, fn _auth ->
      since =
        case Integer.parse(conn.query_params["since"] || "0") do
          {n, _} -> n
          _ -> 0
        end

      send_json(conn, 200, %{events: LearningAgent.Activity.since(since)})
    end)
  end

  get "/v1/graphs" do
    with_model_access(conn, :viewer, fn _auth ->
      send_json(conn, 200, GraphCatalog.list())
    end)
  end

  post "/v1/graphs/start-all" do
    with_model_access(conn, :operator, fn _auth ->
      {:ok, payload} = GraphCatalog.start_all()
      send_json(conn, 200, payload)
    end)
  end

  post "/v1/graphs/relearn-all" do
    with_model_access(conn, :operator, fn _auth ->
      {:ok, payload} = GraphCatalog.relearn_all()
      send_json(conn, 200, payload)
    end)
  end

  post "/v1/graphs/stop-all" do
    with_model_access(conn, :operator, fn _auth ->
      {:ok, payload} = GraphCatalog.stop_all()
      send_json(conn, 200, payload)
    end)
  end

  post "/v1/graphs/:name/start" do
    with_model_access(conn, :operator, fn _auth ->
      case GraphCatalog.start(name) do
        {:ok, payload} ->
          send_json(conn, 200, payload)

        {:error, :not_found} ->
          send_json(conn, 404, %{error: :not_found, message: "graph is not in Codebase Memory"})

        {:error, reason} ->
          send_json(conn, 422, %{error: :invalid_request, message: ops_error_message(reason)})
      end
    end)
  end

  post "/v1/graphs/:name/stop" do
    with_model_access(conn, :operator, fn _auth ->
      case GraphCatalog.stop(name) do
        {:ok, payload} ->
          send_json(conn, 200, payload)

        {:error, :not_found} ->
          send_json(conn, 404, %{error: :not_found, message: "graph is not learning"})

        {:error, reason} ->
          send_json(conn, 422, %{error: :invalid_request, message: ops_error_message(reason)})
      end
    end)
  end

  get "/v1/repositories" do
    with_model_access(conn, :viewer, fn _auth ->
      send_json(conn, 200, %{
        repositories: Enum.map(RepositoryContext.all(), &OperatorBoard.surface_repo/1)
      })
    end)
  end

  post "/v1/repositories" do
    with_model_access(conn, :operator, fn _auth ->
      case repository_params(conn.body_params) do
        {:ok, attrs} ->
          case RepositoryContext.register(attrs) do
            {:ok, repo} ->
              send_json(conn, 201, %{repository: OperatorBoard.surface_repo(repo)})

            {:error, _changeset} ->
              send_json(conn, 422, %{
                error: :invalid_request,
                message: "repository could not be registered"
              })
          end

        {:error, reason} ->
          send_json(conn, 422, %{error: :invalid_request, message: ops_error_message(reason)})
      end
    end)
  end

  get "/v1/runs" do
    with_model_access(conn, :viewer, fn _auth ->
      snapshot = OperatorBoard.snapshot()
      send_json(conn, 200, %{runs: snapshot.runs, counts: snapshot.run_counts})
    end)
  end

  post "/v1/repositories/:id/runs" do
    with_model_access(conn, :operator, fn _auth ->
      case RepositoryContext.queue_pass(id, pin_params(conn.body_params)) do
        {:ok, run} ->
          send_json(conn, 201, %{run: OperatorBoard.surface_run(run)})

        {:error, :not_found} ->
          send_json(conn, 404, %{error: :not_found})

        {:error, _reason} ->
          send_json(conn, 422, %{
            error: :invalid_request,
            message: "could not queue a learning pass"
          })
      end
    end)
  end

  post "/v1/runs/:id/cancel" do
    with_model_access(conn, :operator, fn _auth ->
      case RunContext.request_cancel(id) do
        {:ok, run} ->
          send_json(conn, 200, %{run: id, state: run.state, cancelled: run.cancel_requested})
      end
    end)
  end

  post "/v1/runs/:id/resolve-blocker" do
    with_model_access(conn, :operator, fn _auth ->
      case Repo.get(Run, id) do
        nil ->
          send_json(conn, 404, %{error: :not_found})

        run ->
          case RunContext.unfenced_transition(run.id, run.state, "queued") do
            {:ok, _} ->
              send_json(conn, 200, %{run: id, state: "queued"})

            {:error, _} ->
              send_json(conn, 422, %{
                error: :invalid_request,
                message: "run cannot return to queued"
              })
          end
      end
    end)
  end

  get "/v1/settings" do
    with_model_access(conn, :viewer, fn _auth ->
      send_json(conn, 200, RuntimeSettings.snapshot())
    end)
  end

  put "/v1/settings" do
    with_model_access(conn, :operator, fn _auth ->
      case settings_params(conn.body_params) do
        {:ok, attrs} ->
          with {:ok, snapshot} <- apply_settings(attrs) do
            send_json(conn, 200, snapshot)
          else
            {:error, reason} ->
              send_json(conn, 422, %{error: :invalid_request, message: ops_error_message(reason)})
          end

        {:error, reason} ->
          send_json(conn, 422, %{error: :invalid_request, message: ops_error_message(reason)})
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

  defp model_connection_params(params) when is_map(params) do
    allowed = MapSet.new(["base_url", "api_key"])

    if Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)) do
      base_url = Map.get(params, "base_url")
      api_key = Map.get(params, "api_key")

      if (is_nil(base_url) or is_binary(base_url)) and (is_nil(api_key) or is_binary(api_key)) do
        {:ok, %{base_url: blank_to_nil(base_url), api_key: blank_to_nil(api_key)}}
      else
        {:error, :connection_invalid}
      end
    else
      {:error, :unknown_fields}
    end
  end

  defp model_connection_params(_), do: {:error, :invalid_json}

  defp model_test_params(params) when is_map(params) do
    allowed = MapSet.new(["prompt", "model", "base_url", "api_key"])

    if Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)) do
      prompt = Map.get(params, "prompt")
      model = Map.get(params, "model")
      base_url = Map.get(params, "base_url")
      api_key = Map.get(params, "api_key")

      cond do
        not is_binary(prompt) ->
          {:error, :prompt_required}

        is_nil(model) or is_binary(model) ->
          {:ok,
           {prompt, if(model == "", do: nil, else: model),
            %{base_url: blank_to_nil(base_url), api_key: blank_to_nil(api_key)}}}

        true ->
          {:error, :model_invalid}
      end
    else
      {:error, :unknown_fields}
    end
  end

  defp model_test_params(_), do: {:error, :invalid_json}

  defp blank_to_nil(value) when is_binary(value) and value == "", do: nil
  defp blank_to_nil(value), do: value

  defp repository_params(params) when is_map(params) do
    allowed = MapSet.new(["slug", "display_name", "source_locator", "graph_project"])

    if Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)) do
      slug = Map.get(params, "slug")
      display_name = Map.get(params, "display_name")
      source_locator = Map.get(params, "source_locator")
      graph_project = Map.get(params, "graph_project")

      cond do
        not valid_slug?(slug) ->
          {:error, :slug_invalid}

        not present_text?(display_name) ->
          {:error, :display_name_invalid}

        not valid_locator?(source_locator) ->
          {:error, :source_locator_invalid}

        not present_text?(graph_project) ->
          {:error, :graph_project_invalid}

        true ->
          {:ok,
           %{
             slug: slug,
             display_name: display_name,
             source_locator: source_locator,
             graph_project: graph_project
           }}
      end
    else
      {:error, :unknown_fields}
    end
  end

  defp repository_params(_), do: {:error, :invalid_json}

  defp pin_params(params) when is_map(params) do
    %{
      root: blank_to_nil(Map.get(params, "root")),
      branch: blank_to_nil(Map.get(params, "branch")),
      commit_sha: blank_to_nil(Map.get(params, "commit_sha"))
    }
  end

  defp pin_params(_), do: %{}

  defp settings_params(params) when is_map(params) do
    allowed = MapSet.new(["worker_slots", "lanes", "model"])

    if Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)) do
      attrs =
        %{}
        |> maybe_put(:worker_slots, Map.get(params, "worker_slots"))
        |> maybe_put(:lanes, Map.get(params, "lanes"))
        |> maybe_put(:model, Map.get(params, "model"))

      if attrs == %{}, do: {:error, :worker_slots_invalid}, else: {:ok, attrs}
    else
      {:error, :unknown_fields}
    end
  end

  defp settings_params(_), do: {:error, :invalid_json}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_settings(attrs) do
    model = Map.get(attrs, :model)
    base = Map.delete(attrs, :model)

    with {:ok, _} <-
           if(base == %{}, do: {:ok, RuntimeSettings.snapshot()}, else: RuntimeSettings.put(base)),
         {:ok, snapshot} <- apply_model(model) do
      {:ok, snapshot}
    end
  end

  defp apply_model(nil), do: {:ok, RuntimeSettings.snapshot()}

  defp apply_model(model) when is_map(model) do
    RuntimeSettings.put_model_connection(model)
  end

  defp apply_model(_), do: {:error, :model_connection_invalid}

  defp valid_slug?(value) when is_binary(value),
    do: Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,62}$/, value)

  defp valid_slug?(_), do: false

  defp valid_locator?(value) when is_binary(value) do
    present_text?(value) and String.starts_with?(value, "/") and not String.contains?(value, "..")
  end

  defp valid_locator?(_), do: false

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

  defp ops_error_message(:slug_invalid), do: "slug must be lowercase letters, numbers, and dashes"
  defp ops_error_message(:display_name_invalid), do: "display name is required"
  defp ops_error_message(:source_locator_invalid), do: "source locator must be an absolute path"
  defp ops_error_message(:graph_project_invalid), do: "graph project is required"
  defp ops_error_message(:unknown_fields), do: "unknown request fields"

  defp ops_error_message(:worker_slots_invalid),
    do: "worker slots must total 1 to 64 across at most 8 model lanes"

  defp ops_error_message(:model_connection_invalid),
    do: "model connection needs a valid http(s) base URL; api key and model must be valid"

  defp ops_error_message(_), do: "request is invalid"

  defp model_error(conn, %{class: class} = reason) do
    status =
      case class do
        :invalid_request -> 422
        :not_configured -> 503
        :timeout -> 504
        :rate_limited -> 429
        _ -> 502
      end

    send_json(conn, status, %{error: Atom.to_string(class), message: model_error_message(reason)})
  end

  defp model_error_message(%{reason: :prompt_required}), do: "prompt is required"
  defp model_error_message(%{reason: :prompt_too_large}), do: "prompt exceeds the 16 KiB limit"
  defp model_error_message(%{reason: :model_invalid}), do: "model identifier is invalid"
  defp model_error_message(%{reason: :base_url_invalid}), do: "OpenAI-compatible URL is invalid"
  defp model_error_message(%{reason: :api_key_invalid}), do: "API key is invalid or too long"

  defp model_error_message(%{reason: :connection_invalid}),
    do: "model connection settings are invalid"

  defp model_error_message(%{reason: :unknown_fields}), do: "unknown request fields"
  defp model_error_message(%{reason: :invalid_json}), do: "request body must be JSON"
  defp model_error_message(%{reason: :base_url}), do: "model endpoint is not configured"
  defp model_error_message(%{reason: :model}), do: "model identifier is not configured"
  defp model_error_message(%{reason: :disabled}), do: "model gateway is disabled"
  defp model_error_message(%{class: :authentication}), do: "model provider authentication failed"
  defp model_error_message(%{class: :rate_limited}), do: "model provider is rate limited"
  defp model_error_message(%{class: :timeout}), do: "model provider timed out"
  defp model_error_message(%{class: :connection}), do: "model provider is unavailable"

  defp model_error_message(%{class: :malformed_response}),
    do: "model provider returned an invalid response"

  defp model_error_message(_), do: "model request failed"

  defp security_headers(conn) do
    conn
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.put_resp_header("x-frame-options", "DENY")
    |> Plug.Conn.put_resp_header("referrer-policy", "no-referrer")
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'"
    )
  end

  defp with_model_access(conn, role, fun) do
    # Local dogfood stays unauthenticated for loopback peers only: the server
    # binds every interface, so LAN callers still need operator tokens.
    if local_dogfood?() and loopback?(conn), do: fun.(conn), else: with_authorize(conn, role, fun)
  end

  defp loopback?(conn) do
    case Plug.Conn.get_peer_data(conn).address do
      {127, 0, 0, 1} -> true
      {0, 0, 0, 0, 0, 0, 0, 1} -> true
      _ -> false
    end
  end

  defp local_dogfood? do
    case System.get_env("LA_LOCAL_DOGFOOD") do
      nil -> Application.get_env(:learning_agent, :local_dogfood, false)
      value -> String.downcase(value) in ["1", "true"]
    end
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
    |> security_headers()
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp db_ready? do
    case Repo.query("SELECT 1") do
      {:ok, _} -> true
      _ -> false
    end
  end
end

defmodule LearningAgent.MCP.Bridge do
  @moduledoc """
  Fail-soft Codebase Memory access for the operator surface and learning pass.

  Tests inject `:memory_projects`. Production uses a short-lived MCP client when
  `LA_CBM_HOST`/`LA_CBM_PORT` are set. A missing server is a degraded catalog,
  never an application crash.
  """
  alias LearningAgent.MCP.{Client, CodebaseMemory}

  # The board polls list_projects every few seconds and one call costs seconds
  # of daemon work (58 projects x stats); a short TTL keeps the operator
  # surface responsive while pin_status keeps learning passes fresh.
  @cache_ttl_ms 30_000

  defp cache_get(key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      {at, value} ->
        if System.monotonic_time(:millisecond) - at < @cache_ttl_ms, do: {:ok, value}, else: :miss

      nil ->
        :miss
    end
  end

  defp cache_put(key, value) do
    :persistent_term.put({__MODULE__, key}, {System.monotonic_time(:millisecond), value})
  end

  def list_projects do
    case Application.get_env(:learning_agent, :memory_projects) do
      fun when is_function(fun, 0) -> fun.()
      list when is_list(list) -> {:ok, list}
      _ -> live_list_projects()
    end
  end

  def pin_status(project, expected_root \\ nil) do
    case Application.get_env(:learning_agent, :memory_projects) do
      list when is_list(list) ->
        synthetic_pin(list, project, expected_root)

      fun when is_function(fun, 0) ->
        case fun.() do
          {:ok, list} -> synthetic_pin(list, project, expected_root)
          other -> other
        end

      _ ->
        live_pin_status(project, expected_root)
    end
  end

  defp synthetic_pin(list, project, expected_root) do
    found =
      Enum.find(list, fn
        %{"name" => name} -> name == project
        %{name: name} -> name == project
        name when is_binary(name) -> name == project
        _ -> false
      end)

    case found do
      nil ->
        {:error, :not_found}

      item ->
        root =
          cond do
            is_map(item) ->
              item["root_path"] || item["root"] || Map.get(item, :root_path) ||
                Map.get(item, :root)

            true ->
              expected_root
          end

        {:ok,
         %{
           project: project,
           status: "ready",
           root: root,
           root_agreement: is_nil(expected_root) or root == expected_root,
           parse_partial: %{},
           skipped: %{},
           not_indexed: %{}
         }}
    end
  end

  @doc """
  High-level architecture grounding for a project, cached briefly. Used to
  give learning passes a navigation surface beyond a single file window.
  """
  def architecture(project) do
    case endpoint() do
      {:ok, host, port} ->
        if http_rpc_port?(port) do
          key = {:arch, host, port, project}

          case cache_get(key) do
            {:ok, value} ->
              {:ok, value}

            :miss ->
              case http_tool(host, port, "get_architecture", %{
                     project: project,
                     aspects: ["overview"]
                   }) do
                {:ok, value} = ok ->
                  cache_put(key, value)
                  ok

                other ->
                  other
              end
          end
        else
          {:error, :not_available}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp live_list_projects do
    case endpoint() do
      {:ok, host, port} ->
        if http_rpc_port?(port) do
          key = {:projects, host, port}

          case cache_get(key) do
            {:ok, projects} ->
              {:ok, projects}

            :miss ->
              case http_tool(host, port, "list_projects", %{}) do
                {:ok, %{"projects" => projects}} ->
                  cache_put(key, projects)
                  {:ok, projects}

                {:ok, projects} when is_list(projects) ->
                  cache_put(key, projects)
                  {:ok, projects}

                other ->
                  other
              end
          end
        else
          with_client(&CodebaseMemory.list_projects/1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp live_pin_status(project, expected_root) do
    case endpoint() do
      {:ok, host, port} ->
        if http_rpc_port?(port) do
          key = {:pin, host, port, project, expected_root}

          with {:ok, status} <- fetch_pin_status_cached(key, host, port, project) do
            {:ok,
             %{
               project: project,
               status: status["status"],
               root: status["root_path"],
               root_agreement: is_nil(expected_root) or status["root_path"] == expected_root,
               parse_partial: %{},
               skipped: %{},
               not_indexed: %{}
             }}
          end
        else
          with_client(fn client -> CodebaseMemory.pin_status(client, project, expected_root) end)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_pin_status_cached(key, host, port, project) do
    case cache_get(key) do
      {:ok, status} ->
        {:ok, status}

      :miss ->
        case http_tool(host, port, "index_status", %{project: project}) do
          {:ok, status} when is_map(status) ->
            cache_put(key, status)
            {:ok, status}

          other ->
            other
        end
    end
  end

  defp http_rpc_port?(9749), do: true
  defp http_rpc_port?(_), do: false

  defp http_tool(host, port, name, args) do
    url = "http://#{host}:#{port}/rpc"

    payload =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => name, "arguments" => args}
      })

    _ = Application.ensure_all_started(:inets)

    request =
      {String.to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json",
       payload}

    # A wedged daemon must degrade the operator surface fast (offline) instead
    # of hanging every board poll for 30 seconds.
    case :httpc.request(
           :post,
           request,
           [{:timeout, 8_000}, {:connect_timeout, 3_000}],
           [{:body_format, :binary}]
         ) do
      {:ok, {{_v, status, _r}, _headers, body}} when status in 200..299 ->
        decode_rpc(body)

      _ ->
        {:error, :http_rpc_failed}
    end
  end

  defp decode_rpc(body) do
    case Jason.decode(body) do
      {:ok, %{"result" => %{"content" => [%{"text" => text} | _]}}} ->
        case Jason.decode(text) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> {:error, :malformed_response}
        end

      {:ok, %{"result" => result}} ->
        {:ok, result}

      _ ->
        {:error, :malformed_response}
    end
  end

  defp with_client(fun) do
    case endpoint() do
      {:ok, host, port} ->
        case Client.start_link(host: host, port: port, name: nil) do
          {:ok, pid} ->
            try do
              fun.(pid)
            after
              if Process.alive?(pid), do: GenServer.stop(pid, :normal)
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp endpoint do
    host = Application.get_env(:learning_agent, :cbm_host) || System.get_env("LA_CBM_HOST")

    port =
      Application.get_env(:learning_agent, :cbm_port) || parse_port(System.get_env("LA_CBM_PORT"))

    cond do
      is_binary(host) and host != "" and is_integer(port) -> {:ok, host, port}
      true -> {:error, :not_configured}
    end
  end

  defp parse_port(value) when is_binary(value) do
    case Integer.parse(value) do
      {port, ""} -> port
      _ -> nil
    end
  end

  defp parse_port(_), do: nil
end

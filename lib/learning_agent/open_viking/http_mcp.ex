defmodule LearningAgent.OpenViking.HttpMcp do
  @moduledoc """
  Streamable-HTTP MCP client for the OpenViking server. OpenViking serves MCP
  over POST /mcp: a JSON-RPC request in, an SSE frame out, and an
  mcp-session-id header after initialize. The newline-framed TCP transport in
  LearningAgent.MCP cannot speak that protocol, which is how the OpenViking
  outbox drain stranded every event behind connection errors.
  """

  @connect_timeout 5_000
  @timeout 30_000

  @doc "Initialize a session. Returns {:ok, client} | {:error, reason}."
  def start(host, port) when is_binary(host) and is_integer(port) do
    params = %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "learning-agent", "version" => "0.1.0"}
    }

    case rpc(host, port, nil, "initialize", params) do
      {:ok, _result, session} -> {:ok, {host, port, session}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "One tools/call against an initialized session."
  def call({host, port, session}, tool, params) do
    case rpc(host, port, session, "tools/call", %{"name" => tool, "arguments" => params}) do
      {:ok, result, _session} -> unwrap(result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp unwrap(%{"isError" => true} = result), do: {:error, {:tool_error, result}}
  defp unwrap(result) when is_map(result), do: {:ok, result}
  defp unwrap(other), do: {:error, {:unexpected_result, other}}

  defp rpc(host, port, session, method, params) do
    _ = Application.ensure_all_started(:inets)

    url = String.to_charlist("http://" <> host <> ":" <> Integer.to_string(port) <> "/mcp")

    payload =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})

    headers =
      [
        {~c"content-type", ~c"application/json"},
        {~c"accept", ~c"application/json, text/event-stream"}
      ] ++
        session_headers(session)

    request = {url, headers, ~c"application/json", payload}

    http_opts = [{:timeout, @timeout}, {:connect_timeout, @connect_timeout}]

    case :httpc.request(:post, request, http_opts, [{:body_format, :binary}]) do
      {:ok, {{_version, status, _reason}, response_headers, body}} when status in 200..299 ->
        case decode_sse(body) do
          {:ok, %{"result" => result}} ->
            {:ok, result, session_header(response_headers) || session}

          {:ok, %{"error" => error}} ->
            {:error, {:jsonrpc_error, error}}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp session_headers(nil), do: []
  defp session_headers(session), do: [{~c"mcp-session-id", String.to_charlist(session)}]

  defp session_header(headers) do
    case List.keyfind(headers, ~c"mcp-session-id", 0) do
      {_, value} -> List.to_string(value)
      nil -> nil
    end
  end

  @doc """
  Parse the SSE frame of a Streamable-HTTP MCP response: the first `data:`
  line holding a complete JSON-RPC envelope. Public for tests.
  """
  def decode_sse(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.find_value({:error, :no_data_frame}, fn line ->
      case line do
        "data: " <> rest -> json_or_next(rest)
        "data:" <> rest -> json_or_next(String.trim(rest))
        _ -> nil
      end
    end)
  end

  defp json_or_next(rest) do
    case Jason.decode(rest) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> nil
    end
  end
end

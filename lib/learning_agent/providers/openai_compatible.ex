defmodule LearningAgent.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible chat adapter (docs/02 §8-§9, D-003; ships first).

  Projects provider-neutral messages to the chat-completions wire shape (system/
  user/assistant/tool roles) and normalizes the response (text, tool calls, usage,
  stop reason) and error classes. Transport is injected so tests run without a key;
  production uses HTTP.
  """
  @behaviour LearningAgent.Provider

  @impl true
  def complete(opts) do
    body = build_body(opts)

    transport =
      Map.get(opts, :transport, fn current_body -> http_transport(current_body, opts) end)

    case transport.(body) do
      {:ok, resp} -> normalize_response(resp)
      {:error, reason} -> {:error, %{class: classify_reason(reason), detail: reason}}
    end
  end

  @impl true
  def classify(reason), do: classify_reason(reason)

  @doc "List models from an OpenAI-compatible `/models` endpoint."
  def list_models(opts) when is_map(opts) do
    transport =
      Map.get(opts, :list_transport, fn -> http_models_transport(opts) end)

    case transport.() do
      {:ok, response} -> normalize_models(response)
      {:error, reason} -> {:error, %{class: classify_reason(reason), detail: reason}}
    end
  end

  @impl true
  def estimate_cost(%{usage: %{prompt_tokens: p, completion_tokens: c}}), do: p + c
  def estimate_cost(_), do: :unknown

  defp normalize_response(%{"choices" => [choice | _]} = response) when is_map(choice) do
    with %{} = message <- Map.get(choice, "message"),
         {:ok, tool_calls} <- normalize_tool_calls(Map.get(message, "tool_calls", [])) do
      {:ok,
       %{
         text: Map.get(message, "content"),
         tool_calls: tool_calls,
         usage: Map.get(response, "usage", %{}),
         stop_reason: Map.get(choice, "finish_reason")
       }}
    else
      _ -> {:error, %{class: :malformed_response, detail: :missing_message_or_tool_call}}
    end
  end

  defp normalize_response(_),
    do: {:error, %{class: :malformed_response, detail: :missing_choices}}

  defp normalize_tool_calls(calls) when is_list(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, acc} ->
      if is_map(call) do
        function = Map.get(call, "function", %{})

        if is_map(function) and is_binary(Map.get(function, "name")) and
             is_binary(Map.get(function, "arguments")) do
          normalized = %{
            "id" => Map.get(call, "id"),
            "name" => function["name"],
            "arguments" => function["arguments"]
          }

          {:cont, {:ok, [normalized | acc]}}
        else
          {:halt, {:error, :malformed_tool_call}}
        end
      else
        {:halt, {:error, :malformed_tool_call}}
      end
    end)
    |> case do
      {:ok, calls} -> {:ok, Enum.reverse(calls)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_tool_calls(_), do: {:error, :malformed_tool_calls}

  defp build_body(opts) do
    messages = Enum.map(opts.messages, &map_msg/1)

    %{
      "model" => opts.model,
      "messages" => messages,
      "temperature" => Map.get(opts, :temperature, 0.1)
    }
  end

  defp map_msg(%{role: role, content: blocks}) do
    role_str = provider_role(role)
    %{"role" => role_str, "content" => Enum.map_join(blocks, "\n", &block_text/1)}
  end

  defp block_text(%{type: :text, text: t}), do: t
  defp block_text(%{type: :tool_result, content: c}), do: inspect(c)
  defp block_text(x), do: inspect(x)

  defp provider_role(:assistant), do: "assistant"
  defp provider_role(:tool), do: "tool"
  defp provider_role(:temporary_guidance), do: "assistant"
  defp provider_role(_), do: "user"

  defp classify_reason(%{class: c}), do: c
  defp classify_reason({:http_status, status}) when status in [401, 403], do: :authentication
  defp classify_reason({:http_status, 408}), do: :timeout
  defp classify_reason({:http_status, 429}), do: :rate_limited
  defp classify_reason({:http_status, status}) when status >= 500, do: :server
  defp classify_reason({:http_status, _status}), do: :invalid_request
  defp classify_reason({:transport, :timeout}), do: :timeout
  defp classify_reason({:transport, _reason}), do: :connection
  defp classify_reason(:timeout), do: :timeout
  defp classify_reason(:rate_limited), do: :rate_limited
  defp classify_reason(:auth), do: :authentication
  defp classify_reason(:connection), do: :connection
  defp classify_reason(:malformed_response), do: :malformed_response
  defp classify_reason(:response_too_large), do: :malformed_response
  defp classify_reason(_), do: :unknown

  defp normalize_models(response) when is_map(response) do
    entries = Map.get(response, "data") || Map.get(response, "models")

    models =
      entries
      |> List.wrap()
      |> Enum.map(fn
        %{"id" => id} when is_binary(id) -> id
        %{"name" => name} when is_binary(name) -> name
        id when is_binary(id) -> id
        _ -> nil
      end)
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    if models == [],
      do: {:error, %{class: :malformed_response, detail: :missing_models}},
      else: {:ok, models}
  end

  defp normalize_models(_), do: {:error, %{class: :malformed_response, detail: :missing_models}}

  defp http_models_transport(opts) do
    with {:ok, url} <- models_url(Map.get(opts, :base_url)),
         {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      headers =
        [{~c"accept", ~c"application/json"}] ++ authorization_header(Map.get(opts, :api_key))

      timeout = Map.get(opts, :timeout_ms, 15_000)

      case :httpc.request(
             :get,
             {String.to_charlist(url), headers},
             [{:timeout, timeout}, {:connect_timeout, min(timeout, 5_000)}],
             [{:body_format, :binary}]
           ) do
        {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
          if byte_size(response_body) <= 1_048_576,
            do: decode_body(response_body),
            else: {:error, :response_too_large}

        {:ok, {{_version, status, _reason}, _headers, _response_body}} ->
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  defp models_url(base_url) when is_binary(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host, path: path, userinfo: nil, query: nil, fragment: nil} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        base_path = String.trim_trailing(path || "", "/")

        models_path =
          if String.ends_with?(base_path, "/models"), do: base_path, else: base_path <> "/models"

        {:ok, URI.to_string(%{uri | path: models_path})}

      _ ->
        {:error, :invalid_base_url}
    end
  end

  defp models_url(_), do: {:error, :invalid_base_url}

  defp http_transport(body, opts) do
    with {:ok, url} <- completion_url(Map.get(opts, :base_url)),
         {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      headers =
        [{~c"content-type", ~c"application/json"}] ++
          authorization_header(Map.get(opts, :api_key))

      timeout = Map.get(opts, :timeout_ms, 15_000)
      request = {String.to_charlist(url), headers, ~c"application/json", Jason.encode!(body)}

      case :httpc.request(
             :post,
             request,
             [{:timeout, timeout}, {:connect_timeout, min(timeout, 5_000)}],
             [{:body_format, :binary}]
           ) do
        {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
          decode_body(response_body)

        {:ok, {{_version, status, _reason}, _headers, _response_body}} ->
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  defp authorization_header(key) when is_binary(key) and key != "",
    do: [{~c"authorization", String.to_charlist("Bearer " <> key)}]

  defp authorization_header(_), do: []

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :malformed_response}
    end
  end

  defp completion_url(base_url) when is_binary(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host, path: path, userinfo: nil, query: nil, fragment: nil} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        base_path = String.trim_trailing(path || "", "/")

        completion_path =
          if String.ends_with?(base_path, "/chat/completions"),
            do: base_path,
            else: base_path <> "/chat/completions"

        {:ok, URI.to_string(%{uri | path: completion_path})}

      _ ->
        {:error, :invalid_base_url}
    end
  end

  defp completion_url(_), do: {:error, :invalid_base_url}
end

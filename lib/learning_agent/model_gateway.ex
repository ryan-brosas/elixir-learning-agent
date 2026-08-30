defmodule LearningAgent.ModelGateway do
  @moduledoc "Safe operator-facing gateway for a configured model test."

  alias LearningAgent.Providers.OpenAICompatible

  @max_prompt_bytes 16_384
  @max_model_bytes 128
  @max_base_url_bytes 2_048
  @max_api_key_bytes 512
  @default_timeout_ms 15_000
  @system_prompt "You are the Elixir Learning Agent model test endpoint. Reply concisely and do not call tools."

  @doc """
  Server-side model connection for internal learning calls. Never serialized to
  clients: the playground only receives the redacted catalog.
  """
  def connection do
    s = settings()

    %{
      enabled: s.enabled,
      base_url: s.base_url,
      api_key: s.api_key,
      timeout_ms: s.timeout_ms,
      model: s.model
    }
  end

  @doc "Return non-secret model configuration suitable for the browser."
  def catalog do
    settings = settings()

    %{
      adapter: "openai_compatible",
      configured: configured?(settings),
      model: present_or_nil(settings.model),
      endpoint: endpoint_label(settings.base_url),
      api_key_configured: present?(settings.api_key),
      capabilities: ["chat", "normalized_usage", "tool_call_normalization"]
    }
  end

  @doc "List models using configured or ephemeral browser-supplied connection settings."
  def available_models(connection \\ nil) do
    with :ok <- validate_connection(connection),
         {:ok, settings} <- available_connection_settings(connection),
         {:ok, models} <- OpenAICompatible.list_models(list_options(settings)) do
      {:ok, %{models: models, endpoint: endpoint_label(settings.base_url)}}
    end
  end

  @doc "Run one bounded, non-tool completion using configured or ephemeral browser-supplied connection settings."
  def test(prompt, requested_model \\ nil, connection \\ nil)

  def test(prompt, requested_model, connection) when is_binary(prompt) do
    with :ok <- validate_prompt(prompt),
         :ok <- validate_model(requested_model),
         :ok <- validate_connection(connection),
         {:ok, settings} <- configured_settings(connection, requested_model),
         {:ok, response} <- complete(settings, prompt, requested_model) do
      {:ok,
       %{
         model: selected_model(settings, requested_model),
         text: response.text || "",
         usage: response.usage || %{},
         stop_reason: response.stop_reason
       }}
    end
  end

  def test(_prompt, _requested_model, _connection), do: error(:prompt_required)

  defp complete(settings, prompt, requested_model) do
    opts = %{
      model: selected_model(settings, requested_model),
      messages: [
        %{role: :system, content: [%{type: :text, text: @system_prompt}]},
        %{role: :operator, content: [%{type: :text, text: prompt}]}
      ],
      base_url: settings.base_url,
      api_key: settings.api_key,
      timeout_ms: settings.timeout_ms
    }

    opts =
      case settings.transport do
        transport when is_function(transport, 1) -> Map.put(opts, :transport, transport)
        _ -> opts
      end

    OpenAICompatible.complete(opts)
  end

  defp available_connection_settings(connection) do
    effective = apply_connection(settings(), connection)

    cond do
      not effective.enabled -> not_configured(:disabled)
      not present?(effective.base_url) -> not_configured(:base_url)
      not valid_endpoint?(effective.base_url) -> error(:base_url_invalid)
      true -> {:ok, effective}
    end
  end

  defp list_options(settings) do
    options = %{
      base_url: settings.base_url,
      api_key: settings.api_key,
      timeout_ms: settings.timeout_ms
    }

    case settings.list_transport do
      transport when is_function(transport, 0) -> Map.put(options, :list_transport, transport)
      _ -> options
    end
  end

  defp configured_settings(connection, requested_model) do
    current = settings()
    effective = apply_connection(current, connection)

    effective =
      if is_binary(requested_model), do: %{effective | model: requested_model}, else: effective

    cond do
      not effective.enabled -> not_configured(:disabled)
      not present?(effective.base_url) -> not_configured(:base_url)
      not valid_endpoint?(effective.base_url) -> error(:base_url_invalid)
      not present?(effective.model) -> not_configured(:model)
      true -> {:ok, effective}
    end
  end

  defp configured?(settings),
    do:
      settings.enabled and present?(settings.base_url) and valid_endpoint?(settings.base_url) and
        present?(settings.model)

  defp apply_connection(settings, nil), do: settings

  defp apply_connection(settings, connection) do
    %{
      settings
      | base_url: Map.get(connection, :base_url) || settings.base_url,
        api_key: Map.get(connection, :api_key) || settings.api_key
    }
  end

  defp selected_model(settings, nil), do: settings.model
  defp selected_model(_settings, model), do: model

  defp validate_prompt(prompt) do
    cond do
      String.trim(prompt) == "" -> error(:prompt_required)
      byte_size(prompt) > @max_prompt_bytes -> error(:prompt_too_large)
      true -> :ok
    end
  end

  defp validate_model(nil), do: :ok

  defp validate_model(model) when is_binary(model) do
    if byte_size(model) <= @max_model_bytes and Regex.match?(~r/^[A-Za-z0-9._:~\/-]+$/, model),
      do: :ok,
      else: error(:model_invalid)
  end

  defp validate_model(_), do: error(:model_invalid)

  defp validate_connection(nil), do: :ok

  defp validate_connection(connection) when is_map(connection) do
    base_url = Map.get(connection, :base_url)
    api_key = Map.get(connection, :api_key)

    cond do
      not is_nil(base_url) and not is_binary(base_url) ->
        error(:base_url_invalid)

      is_binary(base_url) and
          (byte_size(base_url) > @max_base_url_bytes or not valid_endpoint?(base_url)) ->
        error(:base_url_invalid)

      not is_nil(api_key) and not is_binary(api_key) ->
        error(:api_key_invalid)

      is_binary(api_key) and byte_size(api_key) > @max_api_key_bytes ->
        error(:api_key_invalid)

      true ->
        :ok
    end
  end

  defp validate_connection(_), do: error(:connection_invalid)
  defp valid_endpoint?(value), do: is_binary(endpoint_label(value))
  defp error(reason), do: {:error, %{class: :invalid_request, reason: reason}}
  defp not_configured(reason), do: {:error, %{class: :not_configured, reason: reason}}

  defp settings do
    configured = Application.get_env(:learning_agent, :model, %{})
    saved = LearningAgent.RuntimeSettings.model_connection() || %{}

    %{
      enabled: read_boolean(configured, :enabled, true),
      base_url:
        saved_value(saved, :base_url) ||
          env_or_config("LA_MODEL_BASE_URL", read(configured, :base_url, nil)),
      model:
        saved_value(saved, :model) ||
          env_or_config("LA_MODEL", read(configured, :model, nil)),
      api_key:
        saved_value(saved, :api_key) ||
          env_or_config("LA_MODEL_API_KEY", read(configured, :api_key, nil)),
      timeout_ms:
        read_timeout(
          System.get_env("LA_MODEL_TIMEOUT_MS"),
          read(configured, :timeout_ms, @default_timeout_ms)
        ),
      transport: read(configured, :transport, nil),
      list_transport: read(configured, :list_transport, nil)
    }
  end

  defp read(configured, key, default) when is_map(configured),
    do: Map.get(configured, key, default)

  defp read(configured, key, default) when is_list(configured),
    do: Keyword.get(configured, key, default)

  defp read(_configured, _key, default), do: default

  defp read_boolean(configured, key, default) do
    case read(configured, key, default) do
      value when is_boolean(value) -> value
      "false" -> false
      "true" -> true
      _ -> default
    end
  end

  defp read_timeout(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed in 1..120_000 -> parsed
      _ -> fallback
    end
  end

  defp read_timeout(_value, fallback), do: fallback

  # Saved Settings override the env defaults (the .env.example documents this
  # contract), field by field: a partial save still falls back per field.
  defp saved_value(saved, key) do
    case Map.get(saved, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp env_or_config(name, configured) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> configured
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp present_or_nil(value), do: if(present?(value), do: value, else: nil)

  defp endpoint_label(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        userinfo: nil,
        query: nil,
        fragment: nil
      }
      when scheme in ["http", "https"] and is_binary(host) ->
        port_suffix = if port in [nil, 80, 443], do: "", else: ":#{port}"
        "#{scheme}://#{host}#{port_suffix}#{String.trim_trailing(path || "", "/")}"

      _ ->
        nil
    end
  end

  defp endpoint_label(_), do: nil
end

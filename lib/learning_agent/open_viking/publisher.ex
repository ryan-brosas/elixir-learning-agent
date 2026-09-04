defmodule LearningAgent.OpenViking.Publisher do
  @moduledoc """
  Drives the OpenViking outbox (docs/03 §16-§18). Claims pending events, dispatches
  to the configured client (add/find/read), marks delivered on success, retries on
  transient failure, records permanent failure. Never deletes OpenViking resources.

  A local-path add returns an upload instruction from OpenViking, not a stored
  resource, so delivery also posts the bytes: the file itself, or a zip archive
  of the directory. Marking delivered before those bytes land would strand the
  copy behind an expiring upload ticket.
  """

  alias LearningAgent.{OutboxContext, OutboxEvent}

  # Bounded parallel dispatch: each event is an add plus a multipart upload,
  # and OpenViking (single uvicorn worker) answers ~500s and timeouts past a
  # small fan-in. The DB pool stays well under its dev default of 10.
  @concurrency 3
  @upload_timeout 60_000

  @doc "Process one claim batch. Returns {:ok, results}."
  def drain(client, limit \\ 10) do
    {:ok, claimed} = OutboxContext.claim_pending(limit)

    results =
      claimed
      |> Task.async_stream(&dispatch(client, &1),
        max_concurrency: @concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    {:ok, results}
  end

  defp dispatch(client, %OutboxEvent{event_type: type, payload: payload} = event) do
    case deliver(client, type, payload || %{}, event) do
      {:ok, remote_ref} -> OutboxContext.deliver(event, remote_ref)
      {:error, {:permanent, reason}} -> OutboxContext.fail(event, reason)
      {:error, reason} -> OutboxContext.retry(event, reason)
    end
  end

  defp deliver(client, "add_learning_note", payload, event),
    do: add_and_upload(client, payload, event)

  defp deliver(client, "add_capsule", payload, event),
    do: add_and_upload(client, payload, event)

  defp deliver(client, "materialize_foundation", payload, event),
    do: add_and_upload(client, payload, event)

  defp deliver(client, "verify_symbol", payload, _event) do
    case client.find.(Map.get(payload, "query", ""), []) do
      {:ok, [_hit | _]} -> {:ok, :verified}
      {:ok, []} -> {:error, {:transient, :not_found}}
      other -> other
    end
  end

  defp deliver(_client, type, _payload, _event),
    do: {:error, {:permanent, {:unsupported_event, type}}}

  defp add_and_upload(client, payload, event) when is_map(payload) do
    case Map.get(payload, "path") do
      path when is_binary(path) and path != "" ->
        # The destination lives on the event column; payload copies are legacy.
        destination = event.destination || Map.get(payload, "destination", "")

        case client.add.(destination, kw(payload)) do
          {:ok, result} -> upload_bytes(result, path)
          other -> other
        end

      _ ->
        {:error, {:permanent, :path_missing}}
    end
  end

  defp add_and_upload(_client, _payload, _event), do: {:error, {:permanent, :payload_missing}}

  defp upload_bytes(result, path) do
    case upload_url(result) do
      nil ->
        # Some endpoints ingest directly from the add call; keep its result as ref.
        {:ok, result}

      url ->
        case upload_fun().(url, path) do
          {:ok, root_ref} -> {:ok, root_ref}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp upload_url(result) do
    case Regex.run(~r/(https?:\/\/\S*temp_upload\S*)/i, result_text(result)) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp result_text(%{"structuredContent" => %{"result" => text}}) when is_binary(text), do: text

  defp result_text(%{"content" => content}) when is_list(content) do
    content |> Enum.map(&Map.get(&1, "text", "")) |> Enum.join("\n")
  end

  defp result_text(text) when is_binary(text), do: text
  defp result_text(_), do: ""

  # Test seam: the live upload posts multipart bytes through :httpc.
  defp upload_fun do
    Application.get_env(:learning_agent, :open_viking_upload) || (&http_upload/2)
  end

  defp http_upload(url, path) do
    _ = Application.ensure_all_started(:inets)

    case read_bytes(path) do
      {:ok, {filename, bytes, mime}} ->
        post_multipart(url, filename, bytes, mime)

      {:error, reason} ->
        {:error, {:permanent, {:upload_read_failed, reason}}}
    end
  end

  defp read_bytes(path) do
    if File.dir?(path) do
      case zip_dir(path) do
        {:ok, zip} -> {:ok, {Path.basename(path) <> ".zip", zip, ~c"application/zip"}}
        {:error, reason} -> {:error, reason}
      end
    else
      case File.read(path) do
        {:ok, bytes} -> {:ok, {Path.basename(path), bytes, ~c"application/octet-stream"}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp post_multipart(url, filename, bytes, mime) do
    boundary = "learning-agent-" <> Integer.to_string(System.unique_integer([:positive]))

    body = [
      "--",
      boundary,
      "\r\n",
      "content-disposition: form-data; name=\"file\"; filename=\"",
      filename,
      "\"\r\n",
      "content-type: ",
      mime,
      "\r\n",
      "\r\n",
      bytes,
      "\r\n--",
      boundary,
      "--\r\n"
    ]

    # :httpc's 4-tuple content_type IS the request content-type header; the
    # boundary must live there or the server cannot split the parts.
    content_type =
      ~c"multipart/form-data; boundary=" ++ String.to_charlist(boundary)

    request =
      {String.to_charlist(url), [], content_type, IO.iodata_to_binary(body)}

    case :httpc.request(
           :post,
           request,
           [{:timeout, @upload_timeout}, {:connect_timeout, 5_000}],
           [
             {:body_format, :binary}
           ]
         ) do
      {:ok, {{_v, status, _r}, _headers, resp_body}} when status in 200..299 ->
        case Jason.decode(resp_body) do
          {:ok, %{"result" => %{"root_uri" => root}}} when is_binary(root) -> {:ok, root}
          {:ok, _} -> {:error, :upload_response_invalid}
          {:error, _} -> {:error, :upload_response_invalid}
        end

      {:ok, {{_v, status, _r}, _headers, _body}} ->
        {:error, {:upload_http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp zip_dir(dir) do
    files =
      Path.wildcard(Path.join(dir, "**/*"))
      |> Enum.filter(&File.regular?(&1))
      |> Enum.map(fn file ->
        {String.to_charlist(Path.relative_to(file, dir)), File.read!(file)}
      end)

    case :zip.create(~c"capsule.zip", files, [:memory]) do
      {:ok, {_name, zip_binary}} -> {:ok, zip_binary}
      {:error, reason} -> {:error, reason}
    end
  end

  defp kw(payload), do: Enum.map(payload, fn {k, v} -> {String.to_atom(k), v} end)
end

defmodule LearningAgent.MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 framing + frame classification (docs/06 Milestone 4).

  Newline-delimited JSON; the client owns correlation/timeouts. Enforces an
  oversized-frame guard and classifies requests, responses, notifications.
  """

  @max_frame 16 * 1024 * 1024
  @json_rpc "2.0"

  def max_frame_size, do: @max_frame

  def encode_request(id, method, params \\ %{}) do
    Jason.encode!(%{jsonrpc: @json_rpc, id: id, method: method, params: params}) <> "\n"
  end

  def encode_response(id, result) do
    Jason.encode!(%{jsonrpc: @json_rpc, id: id, result: result}) <> "\n"
  end

  def encode_error(id, code, message) do
    Jason.encode!(%{jsonrpc: @json_rpc, id: id, error: %{code: code, message: message}}) <> "\n"
  end

  def encode_notification(method, params) do
    Jason.encode!(%{jsonrpc: @json_rpc, method: method, params: params}) <> "\n"
  end

  @doc """
  Split a binary into complete frames + trailing incomplete bytes.
  Returns {:ok, frames, rest} | {:error, :frame_too_large}.
  """
  def split_frames(bin) when is_binary(bin) do
    split_frames(bin, "", [])
  end

  # bin is our thread of remaining bytes; acc holds completed lines, carry unfinished
  defp split_frames("", carry, acc), do: {:ok, Enum.reverse(acc), carry}

  defp split_frames(bin, carry, acc) do
    if byte_size(carry) > @max_frame do
      {:error, :frame_too_large}
    else
      chunk = carry <> bin

      case :binary.split(chunk, "\n") do
        [line, rest] ->
          if byte_size(line) > @max_frame do
            {:error, :frame_too_large}
          else
            split_frames(rest, "", [line | acc])
          end

        [_whole] ->
          {:ok, Enum.reverse(acc), chunk}
      end
    end
  end

  @doc "Decode one JSON line into a classified frame."
  def decode_line(line) do
    case Jason.decode(line) do
      {:ok, %{"method" => _} = msg} ->
        if Map.has_key?(msg, "id"), do: {:request, msg}, else: {:notification, msg}

      {:ok, %{"id" => _} = msg} ->
        {:response, msg}

      {:ok, _} ->
        {:unsupported, line}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end

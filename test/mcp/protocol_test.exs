defmodule LearningAgent.MCP.ProtocolTest do
  use ExUnit.Case, async: true
  alias LearningAgent.MCP.Protocol

  test "encodes a request with id, method, params" do
    frame = Protocol.encode_request(7, "index_status", %{project: "requests"})
    assert frame =~ ~s("method":"index_status")
    assert frame =~ ~s("id":7)
    assert String.ends_with?(frame, "\n")
  end

  test "split_frames groups complete lines and keeps the trailing partial" do
    a = Protocol.encode_response(1, %{ok: true})
    b = Protocol.encode_response(2, %{ok: false})
    {:ok, frames, rest} = Protocol.split_frames(a <> b)
    assert length(frames) == 2
    assert rest == ""
  end

  test "split_frames keeps an incomplete trailing frame" do
    a = Protocol.encode_response(1, %{ok: true})
    partial = String.slice(a, 0, byte_size(a) - 1)
    {:ok, frames, rest} = Protocol.split_frames(partial)
    assert frames == []
    assert rest == partial
  end

  test "a full line plus a pipelined next request decodes correctly" do
    a = Protocol.encode_response(3, %{ok: true})
    b = Protocol.encode_error(4, -32601, "method not found")
    {:ok, frames, ""} = Protocol.split_frames(a <> b)
    assert length(frames) == 2
  end

  test "decode_line classifies request, response, notification" do
    {:request, %{"method" => m}} =
      Protocol.decode_line(String.trim(Protocol.encode_request(5, "ping", %{})))

    assert m == "ping"

    {:response, %{"result" => _}} =
      Protocol.decode_line(Protocol.encode_response(5, %{}) |> String.trim())

    {:notification, _} =
      Protocol.decode_line(Protocol.encode_notification("n", %{}) |> String.trim())
  end

  test "invalid json yields an error" do
    assert {:error, :invalid_json} = Protocol.decode_line("not json")
  end
end

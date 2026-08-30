defmodule LearningAgent.OpenViking.HttpMcpTest do
  use ExUnit.Case, async: true
  alias LearningAgent.OpenViking.HttpMcp

  describe "decode_sse/1" do
    test "parses the data frame of a Streamable-HTTP MCP response" do
      body = """
      event: message
      data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"status\":\"ok\"}}

      """

      assert {:ok, %{"result" => %{"status" => "ok"}} = frame} = HttpMcp.decode_sse(body)
      assert frame["jsonrpc"] == "2.0"
    end

    test "skips non-data lines and keeps scanning malformed data frames" do
      body = """
      event: ping
      data: not-json
      data: {\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32600}}
      """

      assert {:ok, %{"error" => %{"code" => -32600}} = frame} = HttpMcp.decode_sse(body)
      assert frame["id"] == 2
    end

    test "returns an error when no data frame exists" do
      assert {:error, :no_data_frame} = HttpMcp.decode_sse("event: message\n\n")
    end
  end
end

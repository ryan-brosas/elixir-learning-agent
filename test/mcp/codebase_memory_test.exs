defmodule LearningAgent.MCP.CodebaseMemoryTest do
  use ExUnit.Case, async: false
  alias LearningAgent.MCP.{Client, CodebaseMemory, MockServer}

  @index_status %{
    "status" => "ready",
    "root_path" => "/mnt/hdd/utopia/inspo/requests",
    "parse_partial" => %{
      "files" => [%{"path" => "tox.ini", "error_ranges" => "8-9"}],
      "count" => 1
    },
    "skipped" => %{"files" => [], "count" => 0},
    "not_indexed" => %{
      "files" => [%{"path" => "x.png", "reason" => "ignored-suffix"}],
      "count" => 1
    },
    "coverage_note" => "best-effort"
  }

  defp start_client(script) do
    server = MockServer.start(script)

    {:ok, client} =
      Client.start_link(host: "127.0.0.1", port: server.port, name: :cbm_test_client)

    {server, client}
  end

  test "list_projects round-trips over the real socket" do
    {_server, client} =
      start_client([{"list_projects", %{"projects" => [%{"name" => "requests"}]}}])

    assert {:ok, [%{"name" => "requests"}]} = CodebaseMemory.list_projects(client)
  end

  test "index_status returns ready and pin_status computes root agreement" do
    {_server, client} = start_client([{"index_status", @index_status}])
    assert {:ok, %{"status" => "ready"}} = CodebaseMemory.index_status(client, "requests")
    {:ok, pin} = CodebaseMemory.pin_status(client, "requests", "/mnt/hdd/utopia/inspo/requests")
    assert pin.status == "ready"
    assert pin.root_agreement
    assert pin.parse_partial.count == 1
    assert pin.not_indexed.count == 1
  end

  test "pin_status reports root mismatch against an expected root" do
    {_server, client} = start_client([{"index_status", @index_status}])
    {:ok, pin} = CodebaseMemory.pin_status(client, "requests", "/some/other/path")
    refute pin.root_agreement
    assert pin.root == "/mnt/hdd/utopia/inspo/requests"
  end

  test "get_code_snippet returns source and anchors" do
    snippet = %{
      "source" => "class Request:",
      "name" => "Request",
      "file_path" => "src/requests/models.py",
      "start_line" => 284,
      "end_line" => 375
    }

    {_server, client} = start_client([{"get_code_snippet", snippet}])
    {:ok, got} = CodebaseMemory.get_code_snippet(client, "requests", "requests.models.Request")
    assert got["source"] == "class Request:"
  end
end

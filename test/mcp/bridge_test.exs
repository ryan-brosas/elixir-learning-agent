defmodule LearningAgent.MCP.BridgeTest do
  use ExUnit.Case, async: false
  alias LearningAgent.MCP.{Bridge, MockServer}

  test "injected memory_projects remain the catalog source" do
    previous = Application.get_env(:learning_agent, :memory_projects)
    Application.put_env(:learning_agent, :memory_projects, [%{"name" => "injected"}])

    try do
      assert {:ok, [%{"name" => "injected"}]} = Bridge.list_projects()
    after
      restore(previous)
    end
  end

  test "live list_projects uses a short-lived MCP client" do
    server = MockServer.start([{"list_projects", %{"projects" => [%{"name" => "live-graph"}]}}])
    previous_host = Application.get_env(:learning_agent, :cbm_host)
    previous_port = Application.get_env(:learning_agent, :cbm_port)
    previous_projects = Application.get_env(:learning_agent, :memory_projects)
    Application.delete_env(:learning_agent, :memory_projects)
    Application.put_env(:learning_agent, :cbm_host, "127.0.0.1")
    Application.put_env(:learning_agent, :cbm_port, server.port)

    try do
      assert {:ok, [%{"name" => "live-graph"}]} = Bridge.list_projects()
    after
      restore_env(:cbm_host, previous_host)
      restore_env(:cbm_port, previous_port)
      restore(previous_projects)
    end
  end

  test "missing MCP endpoint is a degraded miss, not a crash" do
    previous_projects = Application.get_env(:learning_agent, :memory_projects)
    previous_host = Application.get_env(:learning_agent, :cbm_host)
    previous_port = Application.get_env(:learning_agent, :cbm_port)
    Application.delete_env(:learning_agent, :memory_projects)
    Application.delete_env(:learning_agent, :cbm_host)
    Application.delete_env(:learning_agent, :cbm_port)

    try do
      assert {:error, :not_configured} = Bridge.list_projects()
    after
      restore(previous_projects)
      restore_env(:cbm_host, previous_host)
      restore_env(:cbm_port, previous_port)
    end
  end

  defp restore(nil), do: Application.delete_env(:learning_agent, :memory_projects)
  defp restore(value), do: Application.put_env(:learning_agent, :memory_projects, value)

  defp restore_env(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore_env(key, value), do: Application.put_env(:learning_agent, key, value)
end

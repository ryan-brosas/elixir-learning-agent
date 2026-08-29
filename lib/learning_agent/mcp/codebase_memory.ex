defmodule LearningAgent.MCP.CodebaseMemory do
  @moduledoc """
  Typed operations over the Codebase Memory MCP server (docs/06 M4).

  Normalizes responses into plain maps. The project is addressed by its name;
  source symbols by qualified_name. Argument names were ground-truthed by probing
  the live server in Milestone 0: list_projects, index_status(%{project}),
  get_code_snippet(%{project, qualified_name}).
  """
  alias LearningAgent.MCP.Client

  def list_projects(client) do
    case Client.call(client, "list_projects") do
      {:ok, %{"projects" => projects}} -> {:ok, projects}
      other -> other
    end
  end

  def index_status(client, project) do
    case Client.call(client, "index_status", %{project: project}) do
      {:ok, %{"status" => _} = status} -> {:ok, status}
      other -> other
    end
  end

  def get_code_snippet(client, project, qualified_name) do
    case Client.call(client, "get_code_snippet", %{
           project: project,
           qualified_name: qualified_name
         }) do
      {:ok, %{"source" => _} = msg} -> {:ok, msg}
      other -> other
    end
  end

  def pin_status(client, project, expected_root \\ nil) do
    case index_status(client, project) do
      {:ok, status} ->
        {:ok,
         %{
           project: project,
           status: status["status"],
           root: status["root_path"],
           root_agreement: is_nil(expected_root) or status["root_path"] == expected_root,
           parse_partial: coverage_fields(status, "parse_partial"),
           skipped: coverage_fields(status, "skipped"),
           not_indexed: coverage_fields(status, "not_indexed")
         }}

      error ->
        error
    end
  end

  defp coverage_fields(status, key) do
    case Map.get(status, key) do
      nil -> %{}
      map when is_map(map) -> %{count: map["count"], files: Map.get(map, "files", [])}
    end
  end
end

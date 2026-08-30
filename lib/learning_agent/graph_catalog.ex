defmodule LearningAgent.GraphCatalog do
  @moduledoc """
  Codebase Memory graphs as the operator start/stop surface.

  One graph maps to one repository. A worker holds at most one repository lease,
  so learning is one repo at a time per worker. OpenViking remains the outbox
  publication plane, not the scheduler.
  """
  alias LearningAgent.{OperatorBoard, RepositoryContext, RunContext}

  def list do
    repos = RepositoryContext.all()
    repos_by_graph = Map.new(repos, &{&1.graph_project, &1})
    {memory, projects} = memory_projects()

    graphs =
      projects
      |> Enum.map(&surface(&1, repos_by_graph))
      |> merge_unlisted_repos(repos, projects)

    %{
      memory: memory,
      graphs: graphs,
      worker_slots: LearningAgent.RuntimeSettings.worker_slots(),
      lanes: LearningAgent.RuntimeSettings.snapshot().lanes
    }
  end

  def start(name) when is_binary(name) do
    with {:ok, project} <- fetch_project(name),
         {:ok, repo} <- ensure_repo(project) do
      if LearningAgent.LearningPass.drained?(repo) do
        _ = RepositoryContext.set_status(repo.id, "complete")

        {:ok,
         %{
           repository: OperatorBoard.surface_repo(%{repo | status: "complete"}),
           run: nil,
           started: false,
           drained: true
         }}
      else
        start_active(repo, project)
      end
    end
  end

  def start(_), do: {:error, :graph_invalid}

  defp start_active(repo, project) do
    with {:ok, repo} <- RepositoryContext.set_status(repo.id, "active") do
      case RunContext.active_for(repo.id) do
        %{} = run ->
          {:ok,
           %{
             repository: OperatorBoard.surface_repo(repo),
             run: OperatorBoard.surface_run(run),
             started: false
           }}

        nil ->
          case RepositoryContext.queue_pass(repo.id, pin_attrs(project)) do
            {:ok, run} ->
              {:ok,
               %{
                 repository: OperatorBoard.surface_repo(repo),
                 run: OperatorBoard.surface_run(run),
                 started: true
               }}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  def start_all do
    {_memory, projects} = memory_projects()

    # Codebase Memory offline must not strand registered repositories: fall
    # back to the durable repository table so Start always queues real work.
    names =
      if projects == [] do
        repos = RepositoryContext.all()

        (Enum.map(repos, & &1.graph_project) ++ Enum.map(repos, & &1.slug))
        |> Enum.uniq()
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
      else
        Enum.map(projects, & &1.name)
      end

    {queued, running, drained, errors} =
      Enum.reduce(names, {0, 0, 0, 0}, fn name, {queued, running, drained, errors} ->
        case start(name) do
          {:ok, %{started: true}} -> {queued + 1, running, drained, errors}
          {:ok, %{drained: true}} -> {queued, running, drained + 1, errors}
          {:ok, _} -> {queued, running + 1, drained, errors}
          {:error, _} -> {queued, running, drained, errors + 1}
        end
      end)

    {:ok,
     %{
       queued: queued,
       already_running: running,
       drained: drained,
       errors: errors,
       graphs: length(names)
     }}
  end

  @doc """
  Re-open every completed or stopped repository and queue one fresh pass. A
  drained repo settles back to complete after the pass, so this is an explicit
  re-squeeze. Disabled repositories are included: Stop must never strand the
  fleet, and Re-learn all is the documented way to recover it.
  """
  def relearn_all do
    repos =
      RepositoryContext.all()
      |> Enum.filter(&(&1.status in ["complete", "disabled"]))

    {queued, errors} =
      Enum.reduce(repos, {0, 0}, fn repo, {queued, errors} ->
        case relearn(repo.slug) do
          {:ok, _} -> {queued + 1, errors}
          {:error, _} -> {queued, errors + 1}
        end
      end)

    {:ok, %{queued: queued, errors: errors, graphs: length(repos)}}
  end

  @doc "Re-open one completed repository and queue a fresh pass."
  def relearn(name) when is_binary(name) do
    case RepositoryContext.get_by_graph(name) || RepositoryContext.get_by_slug(slugify(name)) do
      nil ->
        {:error, :not_found}

      repo ->
        with {:ok, repo} <- RepositoryContext.set_status(repo.id, "active"),
             {:ok, run} <- RepositoryContext.queue_pass(repo.id) do
          {:ok,
           %{
             repository: OperatorBoard.surface_repo(repo),
             run: OperatorBoard.surface_run(run),
             started: true,
             relearned: true
           }}
        end
    end
  end

  def relearn(_), do: {:error, :graph_invalid}

  def stop_all do
    cancelled =
      Enum.reduce(RepositoryContext.all(), 0, fn repo, n ->
        _ = RepositoryContext.set_status(repo.id, "disabled")

        case RunContext.active_for(repo.id) do
          nil ->
            n

          run ->
            _ = RunContext.request_cancel(run.id)
            n + 1
        end
      end)

    {:ok, %{cancelled: cancelled}}
  end

  def stop(name) when is_binary(name) do
    case RepositoryContext.get_by_graph(name) || RepositoryContext.get_by_slug(slugify(name)) do
      nil ->
        {:error, :not_found}

      repo ->
        {:ok, repo} = RepositoryContext.set_status(repo.id, "disabled")

        cancelled =
          case RunContext.active_for(repo.id) do
            nil ->
              []

            run ->
              case RunContext.request_cancel(run.id) do
                {:ok, updated} -> [OperatorBoard.surface_run(updated)]
                _ -> [OperatorBoard.surface_run(run)]
              end
          end

        {:ok, %{repository: OperatorBoard.surface_repo(repo), cancelled: cancelled}}
    end
  end

  def stop(_), do: {:error, :graph_invalid}

  defp memory_projects do
    LearningAgent.MCP.Bridge.list_projects()
    |> normalize_projects()
  end

  defp normalize_projects({:ok, list}) when is_list(list) do
    {%{available: true}, Enum.map(list, &normalize_project/1) |> Enum.reject(&is_nil/1)}
  end

  defp normalize_projects({:error, reason}), do: {%{available: false, reason: reason}, []}
  defp normalize_projects(_), do: {%{available: false, reason: :not_configured}, []}

  defp normalize_project(name) when is_binary(name), do: %{name: name, root: default_root(name)}

  defp normalize_project(%{"name" => name} = project) when is_binary(name) do
    %{name: name, root: project["root_path"] || project["root"] || default_root(name)}
  end

  defp normalize_project(%{name: name} = project) when is_binary(name) do
    %{
      name: name,
      root: Map.get(project, :root) || Map.get(project, :root_path) || default_root(name)
    }
  end

  defp normalize_project(_), do: nil

  defp fetch_project(name) do
    {_memory, projects} = memory_projects()

    case Enum.find(projects, &(&1.name == name)) do
      nil -> fallback_project(name)
      project -> {:ok, project}
    end
  end

  # Durable fallback: a registered repository is startable even when the
  # Codebase Memory MCP is unreachable.
  defp fallback_project(name) do
    repo =
      RepositoryContext.get_by_graph(name) ||
        RepositoryContext.get_by_slug(slugify(name))

    if repo do
      {:ok, %{name: repo.graph_project, root: repo.source_locator}}
    else
      {:error, :not_found}
    end
  end

  defp ensure_repo(project) do
    slug = slugify(project.name)

    case RepositoryContext.get_by_graph(project.name) || RepositoryContext.get_by_slug(slug) do
      %{} = repo ->
        {:ok, repo}

      nil ->
        RepositoryContext.register(%{
          slug: slug,
          display_name: project.name,
          graph_project: project.name,
          source_locator: project.root || default_root(project.name)
        })
    end
  end

  defp pin_attrs(project), do: %{root: project.root, branch: "main"}

  defp surface(nil, _), do: nil

  defp surface(project, repos_by_graph) do
    repo = Map.get(repos_by_graph, project.name)
    run = repo && RunContext.active_for(repo.id)
    learning = learning_state(repo, run)

    %{
      name: project.name,
      root: project.root,
      learning: learning,
      repository: repo && OperatorBoard.surface_repo(repo),
      run: run && OperatorBoard.surface_run(run)
    }
  end

  defp merge_unlisted_repos(graphs, repos, projects) do
    known = MapSet.new(Enum.map(projects, & &1.name))

    extras =
      repos
      |> Enum.reject(&MapSet.member?(known, &1.graph_project))
      |> Enum.map(fn repo ->
        surface(%{name: repo.graph_project, root: repo.source_locator}, %{
          repo.graph_project => repo
        })
      end)

    Enum.reject(graphs ++ extras, &is_nil/1)
  end

  defp learning_state(nil, _), do: "idle"
  defp learning_state(%{status: "disabled"}, _), do: "idle"
  defp learning_state(%{status: "complete"}, _), do: "drained"
  defp learning_state(_repo, %{state: "queued"}), do: "queued"
  defp learning_state(_repo, %{}), do: "learning"
  defp learning_state(_repo, _), do: "idle"

  defp default_root(name), do: Path.join("/sources", slugify(name))

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 63)
  end
end

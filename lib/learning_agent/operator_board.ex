defmodule LearningAgent.OperatorBoard do
  @moduledoc "Read-only operator snapshot for the learning control-plane UI."

  import Ecto.Query
  alias LearningAgent.{Repo, Run, OutboxContext, ModelGateway, RepositoryContext}

  def snapshot do
    repositories = RepositoryContext.all()
    repos_by_id = Map.new(repositories, &{&1.id, &1})
    runs = recent_runs(40)

    catalog = LearningAgent.GraphCatalog.list()

    %{
      health: %{live: true, ready: db_ready?()},
      model: ModelGateway.catalog(),
      memory: catalog.memory,
      worker_slots: catalog.worker_slots,
      lanes: catalog.lanes,
      repository_count: length(repositories),
      run_counts: run_counts(),
      outbox_backlog: OutboxContext.backlog(),
      graphs: catalog.graphs,
      repositories: Enum.map(repositories, &surface_repo/1),
      runs: Enum.map(runs, &surface_run(&1, repos_by_id))
    }
  end

  def recent_runs(limit) when is_integer(limit) and limit in 1..200 do
    from(r in Run, order_by: [desc: r.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  defp run_counts do
    from(r in Run, group_by: r.state, select: {r.state, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  def surface_repo(r) do
    %{
      id: r.id,
      slug: r.slug,
      display_name: r.display_name,
      status: r.status,
      graph_project: r.graph_project,
      source_locator: r.source_locator,
      next_pass_number: r.next_pass_number
    }
  end

  def surface_run(run, repos_by_id \\ %{}) do
    repo = Map.get(repos_by_id, run.repository_id)

    %{
      id: run.id,
      repository_id: run.repository_id,
      repository: repo && repo.slug,
      pass_number: run.pass_number,
      state: run.state,
      outcome: run.outcome,
      blocked_reason: run.blocked_reason,
      failure_class: run.failure_class,
      cancel_requested: run.cancel_requested,
      current_gate: run.current_gate,
      inserted_at: run.inserted_at,
      finished_at: run.finished_at
    }
  end

  defp db_ready? do
    case Repo.query("SELECT 1") do
      {:ok, _} -> true
      _ -> false
    end
  end
end

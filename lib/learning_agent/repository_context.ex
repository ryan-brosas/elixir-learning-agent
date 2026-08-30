defmodule LearningAgent.RepositoryContext do
  @moduledoc """
  Repository registry operations (docs/03 §4, docs/05 §- database/domain tests).
  Uniqueness of slug is enforced by the database unique index; a duplicate insert
  raises an Ecto constraint error that callers classify.
  """
  alias LearningAgent.{Repo, Repository, RepositoryPin}

  def register(attrs) do
    %Repository{}
    |> Repository.changeset(attrs)
    |> Repo.insert()
  end

  def all, do: Repo.all(Repository)

  def get(id), do: Repo.get(Repository, id)

  def get_by_slug(slug), do: Repo.get_by(Repository, slug: slug)

  def get_by_graph(graph_project), do: Repo.get_by(Repository, graph_project: graph_project)

  def add_pin(repository_id, attrs) do
    %RepositoryPin{}
    |> RepositoryPin.changeset(Map.put(attrs, :repository_id, repository_id))
    |> Repo.insert()
  end

  def set_status(id, status) do
    with {:ok, repo} <- fetch(id) do
      repo
      |> Repository.update_status(status)
      |> Repo.update()
    end
  end

  @doc "Queue the next learning pass, creating a pin when the repository has none."
  def queue_pass(id, pin_attrs \\ %{}) do
    Repo.transaction(fn ->
      repo = Repo.get(Repository, id) || Repo.rollback(:not_found)

      pin =
        case latest_pin(repo.id) do
          %RepositoryPin{} = existing -> existing
          nil -> create_pin!(repo, pin_attrs)
        end

      case LearningAgent.RunContext.create(repo.id, pin.id, repo.next_pass_number) do
        {:ok, run} ->
          repo
          |> Ecto.Changeset.change(next_pass_number: repo.next_pass_number + 1)
          |> Repo.update!()

          run

        {:error, changeset} ->
          Repo.rollback({:invalid, changeset})
      end
    end)
  end

  def latest_pin(repository_id) do
    import Ecto.Query

    from(p in RepositoryPin,
      where: p.repository_id == ^repository_id,
      order_by: [desc: p.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp create_pin!(repo, pin_attrs) do
    attrs = %{
      root: Map.get(pin_attrs, :root) || repo.source_locator || repo.canonical_root,
      branch: Map.get(pin_attrs, :branch) || "main",
      commit_sha: Map.get(pin_attrs, :commit_sha) || "unpinned"
    }

    case add_pin(repo.id, attrs) do
      {:ok, pin} -> pin
      {:error, changeset} -> Repo.rollback({:invalid, changeset})
    end
  end

  defp fetch(id) do
    case Repo.get(Repository, id) do
      nil -> {:error, :not_found}
      repo -> {:ok, repo}
    end
  end
end

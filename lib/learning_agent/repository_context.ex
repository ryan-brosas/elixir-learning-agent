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

  defp fetch(id) do
    case Repo.get(Repository, id) do
      nil -> {:error, :not_found}
      repo -> {:ok, repo}
    end
  end
end

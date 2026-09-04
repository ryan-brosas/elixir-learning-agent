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

      pin = select_pin!(repo, pin_attrs)

      case LearningAgent.RunContext.create(repo.id, pin.id, repo.next_pass_number) do
        {:ok, run} ->
          repo
          |> Ecto.Changeset.change(
            next_pass_number: repo.next_pass_number + 1,
            active_pin_id: pin.id
          )
          |> Repo.update!()

          run

        {:error, changeset} ->
          Repo.rollback({:invalid, changeset})
      end
    end)
  end

  @doc "Return the explicitly active pin, falling back to the latest observed pin."
  def current_pin(%Repository{active_pin_id: pin_id} = repository) do
    if pin_id,
      do: Repo.get(RepositoryPin, pin_id) || latest_pin(repository.id),
      else: latest_pin(repository.id)
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

  defp select_pin!(repo, pin_attrs) do
    if requested_pin?(pin_attrs) do
      attrs = normalized_pin(repo, pin_attrs)

      find_pin(repo.id, attrs) || create_pin!(repo, attrs)
    else
      current_pin(repo) || create_pin!(repo, normalized_pin(repo, %{}))
    end
  end

  defp find_pin(repository_id, attrs) do
    import Ecto.Query

    query =
      from(pin in RepositoryPin,
        where:
          pin.repository_id == ^repository_id and pin.root == ^attrs.root and
            pin.branch == ^attrs.branch and pin.commit_sha == ^attrs.commit_sha
      )

    query =
      if is_nil(attrs.graph_generation),
        do: where(query, [pin], is_nil(pin.graph_generation)),
        else: where(query, [pin], pin.graph_generation == ^attrs.graph_generation)

    Repo.one(query)
  end

  defp requested_pin?(attrs) when is_map(attrs) do
    Enum.any?([:root, :branch, :commit_sha, :graph_generation], fn key ->
      value = Map.get(attrs, key)
      not is_nil(value) and value != ""
    end)
  end

  defp requested_pin?(_), do: false

  defp normalized_pin(repo, pin_attrs) do
    %{
      root: Map.get(pin_attrs, :root) || repo.source_locator || repo.canonical_root,
      branch: Map.get(pin_attrs, :branch) || "main",
      commit_sha: Map.get(pin_attrs, :commit_sha) || "unpinned",
      graph_generation: Map.get(pin_attrs, :graph_generation)
    }
  end

  defp create_pin!(repo, attrs) do
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

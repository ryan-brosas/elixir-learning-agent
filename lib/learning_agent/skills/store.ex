defmodule LearningAgent.Skills.Store do
  @moduledoc """
  Compatibility facade for foundation publication.

  Filesystem activation is owned exclusively by `LearningAgent.Artifacts.Publisher`;
  this module cannot bypass journaling or ownership checks.
  """
  alias LearningAgent.Artifacts.Publisher
  alias LearningAgent.Foundations.Projection
  alias LearningAgent.Skills.Root

  @deprecated "use LearningAgent.Foundations.project/3"
  def write_leaf(slug, files) when is_map(files) do
    with {:ok, slug} <- Root.leaf_name(slug),
         :ok <- Projection.validate_files(files),
         {:ok, published} <- Publisher.publish_foundation(Root.path(), slug, files) do
      {:ok, published.active}
    end
  end

  def write_leaf(_, _), do: {:error, :invalid_leaf}
end

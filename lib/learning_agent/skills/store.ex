defmodule LearningAgent.Skills.Store do
  @moduledoc "Write a foundation leaf only under the locked skills root."

  alias LearningAgent.Artifacts.Stager
  alias LearningAgent.Skills.{Leaf, Root}

  def write_leaf(name, files) when is_map(files) do
    with {:ok, name} <- Root.leaf_name(name),
         :ok <- validate_files(files),
         :ok <- parity(files),
         {:ok, staging_root} <- Root.contain(".stage"),
         {:ok, dest} <- Root.contain(name),
         {:ok, staged} <- Stager.stage(staging_root, name, files) do
      File.rm_rf!(dest)
      File.mkdir_p!(Path.dirname(dest))
      File.rename!(staged.root, dest)
      {:ok, dest}
    end
  end

  def write_leaf(_, _), do: {:error, :invalid_leaf}

  defp validate_files(files) do
    if Map.has_key?(files, "SKILL.md"), do: :ok, else: {:error, :missing_skill}
  end

  defp parity(files) do
    refs =
      files
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "references/"))
      |> Enum.sort()

    loader = Leaf.refs_from_loader(Map.get(files, "SKILL.md", ""))
    Leaf.check_parity(loader, refs, refs)
  end
end

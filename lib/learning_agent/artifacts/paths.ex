defmodule LearningAgent.Artifacts.Paths do
  @moduledoc "Pure path resolution for foundation publication. No filesystem mutation occurs here."

  alias LearningAgent.Skills.Root

  @spec foundation(binary(), binary(), binary()) :: {:ok, map()} | {:error, atom()}
  def foundation(root, slug, manifest_digest)
      when is_binary(root) and is_binary(slug) and is_binary(manifest_digest) do
    with {:ok, _} <- Root.leaf_name(slug),
         true <- Regex.match?(~r/^[a-f0-9]{64}$/, manifest_digest) do
      root = Path.expand(root)
      leaf = slug <> "-foundation"
      state = Path.join(root, ".learning-agent")

      {:ok,
       %{
         root: root,
         leaf: leaf,
         active: Path.join(root, leaf),
         legacy: Path.join(root, slug),
         state: state,
         stage: Path.join([state, "stage", leaf, manifest_digest]),
         generation: Path.join([state, "generations", leaf, manifest_digest]),
         legacy_archive: Path.join([state, "legacy", slug]),
         journal_root: Path.join([state, "journals", leaf])
       }}
    else
      _ -> {:error, :invalid_projection_path}
    end
  end

  def foundation(_, _, _), do: {:error, :invalid_projection_path}
end

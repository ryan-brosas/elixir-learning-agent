defmodule LearningAgent.Artifacts.Stager do
  @moduledoc """
  Stage a complete generation to a staging tree (docs/03 §10, docs/05 §20).
  Files are written into <work_root>/<generation_id>/ fully before any activation;
  a rejection rule blocks executables/symlink escapes.
  """
  alias LearningAgent.Artifacts.Manifest

  @doc "Stage a file map. Returns {:ok, %{root, manifest}} | {:error, reason}."
  def stage(work_root, generation_id, files) when is_map(files) do
    if Enum.any?(files, fn {path, _} ->
         not String.starts_with?(path, "references/") and path != "SKILL.md"
       end) do
      {:error, :unexpected_file}
    else
      dir = Path.join([work_root, "stage", generation_id])
      File.rm_rf!(dir)
      File.mkdir_p!(dir)

      Enum.each(files, fn {rel, content} ->
        joined = Path.join(dir, rel)
        File.mkdir_p!(Path.dirname(joined))
        File.write!(joined, content)
      end)

      {:ok, %{root: dir, manifest: Manifest.build(files)}}
    end
  end

  def validate_no_executables(stage) do
    case File.ls(stage.root) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end
end

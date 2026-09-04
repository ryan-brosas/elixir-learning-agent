defmodule LearningAgent.Artifacts.Stager do
  @moduledoc """
  Stages one complete immutable generation before activation.

  Only canonical foundation files are accepted. Existing content-addressed stages
  are read back and reused; no destination tree is recursively removed.
  """
  alias LearningAgent.Artifacts.Manifest

  @owner_file ".learning-agent-foundation.json"

  @doc "Stage a file map below the generic artifact work root."
  def stage(work_root, generation_id, files) when is_map(files) do
    stage_at(Path.join([work_root, "stage", generation_id]), files)
  end

  @doc "Stage a complete generation at a resolved path."
  def stage_at(dir, files) when is_map(files) do
    manifest = Manifest.build(files)

    with :ok <- validate_paths(files),
         :ok <- ensure_stage(dir, files, manifest) do
      {:ok, %{root: dir, manifest: manifest}}
    end
  end

  defp ensure_stage(dir, files, manifest) do
    cond do
      File.exists?(dir) ->
        if verify(dir, manifest), do: :ok, else: {:error, :artifact_conflict}

      true ->
        temp = dir <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

        with :ok <- File.mkdir_p(temp),
             :ok <- write_all(temp, files),
             true <- verify(temp, manifest),
             :ok <- File.mkdir_p(Path.dirname(dir)),
             :ok <- File.rename(temp, dir) do
          :ok
        else
          false ->
            {:error, :verification_failed}

          {:error, :eexist} ->
            if(verify(dir, manifest), do: :ok, else: {:error, :artifact_conflict})

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp write_all(root, files) do
    Enum.reduce_while(files, :ok, fn {relative, content}, :ok ->
      path = Path.join(root, relative)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, content, [:exclusive]) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_paths(files) do
    valid? =
      Enum.all?(files, fn {path, content} ->
        is_binary(path) and is_binary(content) and
          (path == "SKILL.md" or path == @owner_file or
             (String.starts_with?(path, "references/") and Path.extname(path) == ".md")) and
          Path.type(path) == :relative and not String.contains?(path, "..")
      end)

    if valid?, do: :ok, else: {:error, :unexpected_file}
  end

  defp verify(root, manifest) do
    Enum.all?(manifest.files, fn {relative, %{digest: digest}} ->
      case File.read(Path.join(root, relative)) do
        {:ok, content} -> Manifest.digest(content) == digest
        _ -> false
      end
    end)
  end

  def validate_no_executables(_stage), do: :ok
end

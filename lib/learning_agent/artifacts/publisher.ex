defmodule LearningAgent.Artifacts.Publisher do
  @moduledoc """
  The single recoverable filesystem activation boundary for generated artifacts.

  Foundation publication stages a complete content-addressed generation, verifies
  producer ownership, journals intent before mutation, atomically swaps a symlink,
  reads the active generation back, and commits the journal. Unmanaged leaves are
  never removed or overwritten.
  """
  alias LearningAgent.Artifacts.{Journal, Manifest, Paths, Stager}

  @producer "elixir-learning-agent"
  @owner_file ".learning-agent-foundation.json"

  @doc "Legacy generic publisher retained for low-level artifact tests."
  @spec publish(binary(), binary(), map()) :: {:ok, map()} | {:error, atom()}
  def publish(work_root, generation_id, files) do
    with {:ok, staged} <- Stager.stage(work_root, generation_id, files) do
      active = Path.join([work_root, "active", generation_id])
      intent = intent(generation_id, staged.manifest.manifest_digest, staged.root, active)

      with :ok <- Journal.append(work_root, intent),
           :ok <- File.mkdir_p(Path.dirname(active)),
           :ok <- activate_directory(staged.root, active),
           true <- verify(active, staged.manifest),
           :ok <- Journal.commit(work_root, generation_id) do
        {:ok,
         %{active: active, manifest_digest: staged.manifest.manifest_digest, unchanged: false}}
      else
        false -> {:error, :verification_failed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Publish a complete `<slug>-foundation` generation under a skills root."
  def publish_foundation(root, slug, files) when is_map(files) do
    manifest = Manifest.build(files)

    with :ok <- verify_producer_marker(files),
         {:ok, paths} <- Paths.foundation(root, slug, manifest.manifest_digest),
         :ok <- verify_destinations(paths),
         {:ok, staged} <- Stager.stage_at(paths.stage, files),
         :ok <- install_generation(paths, staged.manifest),
         :ok <- Journal.append(paths.journal_root, foundation_intent(paths, manifest)),
         {:ok, unchanged} <- activate_link(paths, manifest),
         true <- verify(paths.active, manifest),
         :ok <- verify_active_owner(paths.active),
         :ok <- Journal.commit(paths.journal_root, manifest.manifest_digest) do
      {:ok,
       %{
         active: paths.active,
         generation_path: paths.generation,
         manifest_digest: manifest.manifest_digest,
         unchanged: unchanged
       }}
    else
      false -> {:error, :verification_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Replay one journaled content-addressed foundation activation."
  def recover_foundation(root, slug, manifest_digest) do
    with {:ok, paths} <- Paths.foundation(root, slug, manifest_digest),
         {:ok, files} <- read_generation(paths.generation),
         true <- Manifest.build(files).manifest_digest == manifest_digest do
      publish_foundation(root, slug, files)
    else
      false -> {:error, :verification_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  def owner_file, do: @owner_file
  def producer, do: @producer

  defp install_generation(paths, manifest) do
    cond do
      File.exists?(paths.generation) ->
        if verify(paths.generation, manifest), do: :ok, else: {:error, :artifact_conflict}

      true ->
        with :ok <- File.mkdir_p(Path.dirname(paths.generation)),
             :ok <- File.rename(paths.stage, paths.generation) do
          :ok
        else
          {:error, :eexist} ->
            if verify(paths.generation, manifest), do: :ok, else: {:error, :artifact_conflict}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp activate_link(paths, manifest) do
    if active_generation?(paths.active, paths.generation, manifest) do
      {:ok, true}
    else
      with :ok <- archive_managed_directory(paths.active, paths.legacy_archive <> "-active"),
           :ok <- archive_legacy(paths),
           :ok <- File.mkdir_p(Path.dirname(paths.active)),
           temp =
             paths.active <> ".next-" <> Integer.to_string(System.unique_integer([:positive])),
           :ok <- File.ln_s(paths.generation, temp),
           :ok <- File.rename(temp, paths.active) do
        {:ok, false}
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp verify_destinations(paths) do
    cond do
      exists?(paths.active) and not managed_active?(paths.active, paths.state) ->
        {:error, :artifact_conflict}

      exists?(paths.legacy) and not managed_leaf?(paths.legacy) ->
        {:error, :artifact_conflict}

      true ->
        :ok
    end
  end

  defp archive_legacy(paths), do: archive_managed_directory(paths.legacy, paths.legacy_archive)

  defp archive_managed_directory(path, archive) do
    case File.lstat(path) do
      {:error, :enoent} ->
        :ok

      {:ok, %File.Stat{type: :directory}} ->
        cond do
          not managed_leaf?(path) -> {:error, :artifact_conflict}
          exists?(archive) -> {:error, :artifact_conflict}
          true -> File.mkdir_p(Path.dirname(archive)) |> then_rename(path, archive)
        end

      {:ok, %File.Stat{type: :symlink}} ->
        :ok

      {:ok, _} ->
        {:error, :artifact_conflict}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp then_rename(:ok, from, to), do: File.rename(from, to)
  defp then_rename({:error, reason}, _from, _to), do: {:error, reason}

  defp managed_active?(path, state) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} ->
        case File.read_link(path) do
          {:ok, target} ->
            expanded = Path.expand(target, Path.dirname(path))

            String.starts_with?(expanded, Path.join(state, "generations") <> "/") and
              managed_leaf?(path)

          _ ->
            false
        end

      {:ok, %File.Stat{type: :directory}} ->
        managed_leaf?(path)

      _ ->
        false
    end
  end

  defp managed_leaf?(path) do
    marker_managed?(path) or legacy_managed?(path)
  end

  defp marker_managed?(path) do
    with {:ok, body} <- File.read(Path.join(path, @owner_file)),
         {:ok, %{"producer" => @producer, "kind" => "foundation"}} <- Jason.decode(body) do
      true
    else
      _ -> false
    end
  end

  # Prior releases had no marker. Recognize only their exact generated shape;
  # arbitrary directories containing SKILL.md are intentionally not sufficient.
  defp legacy_managed?(path) do
    skill = Path.join(path, "SKILL.md")
    references = Path.join(path, "references")

    with {:ok, skill_body} <- File.read(skill),
         true <- String.contains?(skill_body, "## Loader"),
         true <- String.contains?(skill_body, "## Capsule map"),
         {:ok, names} <- File.ls(references),
         true <- names != [],
         true <- Enum.all?(names, &legacy_capsule?(references, &1)) do
      true
    else
      _ -> false
    end
  end

  defp legacy_capsule?(root, name) do
    Path.extname(name) == ".md" and
      case File.read(Path.join(root, name)) do
        {:ok, body} -> String.starts_with?(body, "<!-- capsule-v2 -->")
        _ -> false
      end
  end

  defp active_generation?(active, generation, manifest) do
    with {:ok, %File.Stat{type: :symlink}} <- File.lstat(active),
         {:ok, target} <- File.read_link(active) do
      Path.expand(target, Path.dirname(active)) == Path.expand(generation) and
        verify(active, manifest)
    else
      _ -> false
    end
  end

  defp activate_directory(stage, active) do
    if exists?(active) do
      {:error, :artifact_conflict}
    else
      File.mkdir_p(Path.dirname(active)) |> then_rename(stage, active)
    end
  end

  defp verify(root, manifest) do
    Enum.all?(manifest.files, fn {relative, %{digest: digest}} ->
      case File.read(Path.join(root, relative)) do
        {:ok, content} -> Manifest.digest(content) == digest
        _ -> false
      end
    end)
  end

  defp verify_producer_marker(files) do
    case Map.fetch(files, @owner_file) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"producer" => @producer, "kind" => "foundation"}} -> :ok
          _ -> {:error, :producer_marker_invalid}
        end

      :error ->
        {:error, :producer_marker_missing}
    end
  end

  defp verify_active_owner(path) do
    if marker_managed?(path), do: :ok, else: {:error, :ownership_verification_failed}
  end

  defp read_generation(root) do
    if File.dir?(root) do
      files =
        root
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)
        |> Map.new(fn path -> {Path.relative_to(path, root), File.read!(path)} end)

      {:ok, files}
    else
      {:error, :generation_missing}
    end
  end

  defp foundation_intent(paths, manifest) do
    %{
      "producer" => @producer,
      "kind" => "foundation",
      "manifest_digest" => manifest.manifest_digest,
      "stage" => paths.stage,
      "generation" => paths.generation,
      "active" => paths.active
    }
  end

  defp intent(generation_id, digest, stage, active) do
    %{
      "generation_id" => generation_id,
      "manifest_digest" => digest,
      "stage" => stage,
      "active" => active
    }
  end

  defp exists?(path), do: match?({:ok, _}, File.lstat(path))
end

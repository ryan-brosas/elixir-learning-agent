defmodule LearningAgent.Artifacts.Publisher do
  @moduledoc """
  Recoverable artifact activation (docs/03 §10 §14, docs/05 §20-§23). Sequence:
  stage -> journal intent -> atomic swap stage into active -> verify active against
  manifest -> commit marker. Recovery converges a journal intent to one valid active.
  """
  alias LearningAgent.Artifacts.{Stager, Journal, Manifest}

  @spec publish(binary(), binary(), map()) :: {:ok, map()} | {:error, atom()}
  def publish(work_root, generation_id, files) do
    case Stager.stage(work_root, generation_id, files) do
      {:ok, staged} -> do_publish(work_root, generation_id, staged)
      error -> error
    end
  end

  @spec do_publish(binary(), binary(), map()) :: {:ok, map()} | {:error, atom()}
  defp do_publish(work_root, generation_id, staged) do
    active = Path.join([work_root, "active", generation_id])
    File.mkdir_p!(Path.dirname(active))

    intent = %{
      "generation_id" => generation_id,
      "manifest_digest" => staged.manifest.manifest_digest,
      "stage" => staged.root,
      "active" => active
    }

    Journal.append(work_root, intent)

    backup = active <> ".bak"
    File.rm_rf!(backup)
    if File.exists?(active), do: File.rename!(active, backup)
    File.rename!(staged.root, active)

    manifest = staged.manifest

    if verify_active(active, manifest) do
      Journal.commit(work_root, generation_id)
      {:ok, %{active: active, manifest_digest: manifest.manifest_digest}}
    else
      {:error, :verification_failed}
    end
  end

  defp verify_active(active, manifest) do
    manifest.files
    |> Enum.all?(fn {rel, %{digest: d}} ->
      path = Path.join(active, rel)
      File.exists?(path) and Manifest.digest(File.read!(path)) == d
    end)
  end
end

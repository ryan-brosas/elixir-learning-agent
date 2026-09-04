defmodule LearningAgent.Skills.Leaf do
  @moduledoc """
  Complete foundation-projection loader/map/disk parity (docs/05 §18, docs/10).
  A projection is valid only when loader, capsule map, and on-disk refs agree.
  """

  @doc "Build the loader reference lines for a set of capsule refs."
  def loader_lines(refs), do: Enum.map(refs, fn r -> "- `" <> r <> "` — a porting question." end)

  @doc "Build the capsule-map entries for a set of refs."
  def map_lines(refs),
    do: Enum.map(refs, fn r -> "- **Capability** — `" <> r <> "`: reusable contract." end)

  @doc """
  Parity: loader refs, map refs, and on-disk files must agree bidirectionally.
  Returns :ok | {:error, :loader_map_mismatch | :disk_mismatch}.
  """
  def check_parity(loader_refs, map_refs, disk_refs) do
    cond do
      Enum.sort(loader_refs) != Enum.sort(map_refs) -> {:error, :loader_map_mismatch}
      Enum.sort(loader_refs) != Enum.sort(disk_refs) -> {:error, :disk_mismatch}
      true -> :ok
    end
  end

  @doc "Resolve whether a leaf path is an acceptable activation (real dir OR symlink)."
  def activated?(path) do
    with {:ok, %File.Stat{type: type}} <- File.lstat(path),
         true <- type in [:directory, :symlink] do
      File.exists?(Path.join(path, "SKILL.md"))
    else
      _ -> false
    end
  end

  @doc "Extract references/<...>.md entries from a loader block."
  def refs_from_loader(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "- `references/"))
    |> Enum.map(fn line -> line |> String.split("`") |> Enum.at(1) end)
  end
end

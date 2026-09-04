defmodule LearningAgent.Artifacts.Manifest do
  @moduledoc """
  Complete foundation-projection manifest and content addressing (docs/03, docs/10).
  A manifest lists every file with its SHA-256 and a total `manifest_digest`, so
  unchanged detection, parity, and recovery share one deterministic identity.
  """

  @doc "Build a manifest for a map of {path => content}."
  def build(files) when is_map(files) do
    entries =
      files
      |> Enum.map(fn {path, content} -> {path, %{digest: digest(content)}} end)
      |> Enum.sort_by(&elem(&1, 0))

    identity =
      Enum.map_join(entries, "\n", fn {path, %{digest: file_digest}} ->
        path <> ":" <> file_digest
      end)

    %{
      files: Map.new(entries),
      manifest_digest: digest(identity)
    }
  end

  def digest(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
end

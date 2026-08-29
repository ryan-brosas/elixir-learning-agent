defmodule LearningAgent.Artifacts.Manifest do
  @moduledoc """
  Generation manifest + content-addressing (docs/03 §4 §21, docs/05 §20).
  A manifest lists every file with its SHA-256 and a total manifest_digest, so
  parity and recovery always have one deterministic artifact identity.
  """

  @doc "Build a manifest for a map of {path => content}."
  def build(files) when is_map(files) do
    entries = Enum.map(files, fn {path, content} -> {path, %{digest: digest(content)}} end)

    %{
      files: Map.new(entries),
      manifest_digest: digest(Enum.sort(Enum.map(entries, &elem(&1, 0))) |> Enum.join("|"))
    }
  end

  def digest(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
end

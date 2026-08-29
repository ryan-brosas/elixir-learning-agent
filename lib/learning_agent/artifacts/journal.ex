defmodule LearningAgent.Artifacts.Journal do
  @moduledoc """
  Durable recovery journal (docs/03 §20, docs/05 §21). Records an activation
  intent (generation_id, manifest_digest, stage, active) BEFORE side effects so a
  crash at any point can be reconciled. Written atomically.
  """

  @spec path(binary()) :: binary()
  def path(work_root), do: Path.join(work_root, "activation.journal")

  @doc "Append an activation intent, keyed idempotently by manifest_digest."
  @spec append(binary(), key_value) :: :ok when key_value: map()
  def append(work_root, intent) do
    file = path(work_root)
    File.mkdir_p!(Path.dirname(file))
    entry = Jason.encode!(intent) <> "\n"
    existing = if File.exists?(file), do: File.read!(file), else: ""
    digest_key = intent["manifest_digest"] || Map.get(intent, :manifest_digest, "")

    unless digest_key != "" and String.contains?(existing, digest_key) do
      File.write!(file, existing <> entry)
    end

    :ok
  end

  @doc "Mark an activation committed (idempotent); recovery can then skip it."
  def commit(work_root, generation_id) do
    File.mkdir_p!(Path.dirname(path(work_root)))
    File.write!(Path.join(work_root, "committed_" <> generation_id), "ok")
    :ok
  end

  def read(work_root) do
    file = path(work_root)

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
    else
      []
    end
  end
end

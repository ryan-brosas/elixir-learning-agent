defmodule LearningAgent.Notes do
  @moduledoc """
  Note-first work records (docs/01 §13, docs/05 §16, docs/06 Milestone 6).

  Sequence: validate required sections -> insert canonical SQL note -> materialize
  the Markdown file (temp + atomic rename) -> read back + hash it -> mark the note
  published with file_path/file_digest. publish/2 converges a partial state to one
  canonical published note or an explicit conflict.
  """
  alias LearningAgent.{Repo, LearningNote}
  alias LearningAgent.Notes.Validator

  def schema_version, do: 1

  @doc "Create a draft note in SQL. content is the raw markdown body."
  def create(run_id, repository_id, content) do
    with :ok <- Validator.validate(content) do
      %LearningNote{}
      |> LearningNote.changeset(%{
        run_id: run_id,
        repository_id: repository_id,
        content: content,
        content_digest: digest(content),
        status: "draft"
      })
      |> Repo.insert()
    end
  end

  @doc """
  Materialize the note to a work file, read it back, and mark published when the
  on-disk hash matches the canonical content digest; otherwise mark a conflict.
  """
  def publish(note, work_root) do
    target = file_target(work_root, note)
    File.mkdir_p!(Path.dirname(target))
    temp = target <> ".tmp"
    File.write!(temp, note.content)
    File.rename!(temp, target)

    readback = File.read!(target)
    file_digest = digest(readback)
    status = if file_digest == note.content_digest, do: "published", else: "conflict"

    note
    |> Ecto.Changeset.change(
      status: status,
      file_path: target,
      file_digest: file_digest,
      committed_at: DateTime.utc_now()
    )
    |> Repo.update()
  end

  @doc "Public digest helper (stable SHA-256)."
  def digest(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)

  @doc """
  Recover a partial note after a crash:

  - crash after SQL insert, before file  -> file absent, leave draft (publish can run)
  - crash after file materialize, before status update -> reconcile from the file
  - existing file hash mismatch -> explicit :conflict

  Returns {:ok, reconciled_note} | {:error, :conflict}.
  """
  def recover(note, work_root) do
    target = file_target(work_root, note)

    cond do
      not File.exists?(target) ->
        {:ok, note}

      true ->
        file_digest = digest(File.read!(target))

        if file_digest == note.content_digest do
          ns =
            note
            |> Ecto.Changeset.change(
              status: "published",
              file_path: target,
              file_digest: file_digest,
              committed_at: DateTime.utc_now()
            )
            |> Repo.update()

          ns
        else
          {:error, :conflict}
        end
    end
  end

  defp file_target(work_root, note) do
    sub = String.replace(note.run_id, "-", "")
    Path.join([work_root, sub, "note-" <> sub <> ".md"])
  end
end

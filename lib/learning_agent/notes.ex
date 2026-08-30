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
      attrs = %{
        run_id: run_id,
        repository_id: repository_id,
        content: content,
        content_digest: digest(content),
        status: "draft",
        file_path: nil,
        file_digest: nil,
        committed_at: nil
      }

      case %LearningNote{} |> LearningNote.changeset(attrs) |> Repo.insert() do
        {:ok, note} ->
          {:ok, note}

        {:error, changeset} ->
          if unique_run?(changeset) do
            reuse(run_id, attrs)
          else
            {:error, changeset}
          end
      end
    end
  end

  defp unique_run?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:run_id, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp unique_run?(_), do: false

  defp reuse(run_id, attrs) do
    case Repo.get_by(LearningNote, run_id: run_id) do
      nil ->
        {:error, :not_found}

      note ->
        note
        |> LearningNote.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Materialize the note to a work file, read it back, and mark published when the
  on-disk hash matches the canonical content digest; otherwise mark a conflict.
  """
  def publish(note, work_root) do
    target = file_target(work_root, note)
    temp = target <> ".tmp"

    with :ok <- mkdir(Path.dirname(target)),
         :ok <- write(temp, note.content),
         :ok <- rename(temp, target),
         {:ok, readback} <- File.read(target) do
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
    else
      {:error, :eacces} -> {:error, :not_writable}
      {:error, :eperm} -> {:error, :not_writable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mkdir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp rename(from, to) do
    case File.rename(from, to) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
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
    sub =
      note.run_id
      |> stringify_id()
      |> String.replace("-", "")

    Path.join([work_root, sub, "note-" <> sub <> ".md"])
  end

  defp stringify_id(id) when is_binary(id) and byte_size(id) == 16, do: Ecto.UUID.load!(id)
  defp stringify_id(id) when is_binary(id), do: id
  defp stringify_id(id), do: to_string(id)
end

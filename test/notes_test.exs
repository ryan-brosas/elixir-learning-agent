defmodule LearningAgent.NotesTest do
  use LearningAgent.DataCase, async: false
  alias LearningAgent.{Repo, Notes, RepositoryContext, RunContext}

  defp setup_run(slug) do
    {:ok, repo} =
      RepositoryContext.register(%{
        slug: slug,
        display_name: slug,
        graph_project: slug,
        source_locator: "/sources/" <> slug
      })

    {:ok, pin} =
      RepositoryContext.add_pin(repo.id, %{
        root: "/sources/" <> slug,
        branch: "main",
        commit_sha: "abc"
      })

    {:ok, run} = RunContext.create(repo.id, pin.id, 1)
    {repo, run}
  end

  defp note_body do
    "# architecture\n# covered\n# partial/uncited\n# porter-questions\n# selected-subsystem\n\ncontent"
  end

  test "create inserts a draft note before any file write (note-first)" do
    {_repo, run} = setup_run("n1")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())
    assert note.status == "draft"
    refute note.file_path
  end

  test "publish writes the file and marks it published with a matching hash" do
    work =
      Path.join(
        System.tmp_dir!(),
        "sa_notes_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    {_repo, run} = setup_run("n2")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())
    {:ok, published} = Notes.publish(note, work)
    assert published.status == "published"
    assert is_binary(published.file_digest)
    assert File.exists?(published.file_path)
    File.rm_rf!(work)
  end

  test "publish refuses to overwrite a conflicting materialized note" do
    work =
      Path.join(
        System.tmp_dir!(),
        "immutable_notes_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    {_repo, run} = setup_run("n2c")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())
    {:ok, published} = Notes.publish(note, work)
    File.write!(published.file_path, "operator-owned replacement")

    assert {:error, :conflict} = Notes.publish(note, work)
    assert File.read!(published.file_path) == "operator-owned replacement"
    File.rm_rf!(work)
  end

  test "publish returns not_writable instead of raising" do
    work =
      Path.join(
        System.tmp_dir!(),
        "ro_notes_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(work)
    File.chmod!(work, 0o500)
    {_repo, run} = setup_run("n2b")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())
    assert {:error, :not_writable} = Notes.publish(note, work)
    File.chmod!(work, 0o700)
    File.rm_rf!(work)
  end

  test "a second create for the same run reuses the existing note" do
    {repo, run} = setup_run("n3")
    {:ok, first} = Notes.create(run.id, repo.id, note_body())
    {:ok, second} = Notes.create(run.id, repo.id, note_body())
    assert second.id == first.id
    assert second.status == "draft"
  end

  test "required section names in prose do not satisfy the heading schema" do
    {_repo, run} = setup_run("n3b")

    prose =
      "This mentions architecture, covered, partial/uncited, porter-questions, and selected-subsystem."

    assert {:error, missing} = Notes.create(run.id, run.repository_id, prose)
    assert Enum.sort(missing) == Enum.sort(LearningAgent.Notes.Validator.required_sections())
  end

  test "an invalid note (missing required section) is rejected before DB" do
    {_repo, run} = setup_run("n4")
    assert {:error, missing} = Notes.create(run.id, run.repository_id, "# just a fragment")
    refute Enum.empty?(missing)
  end

  test "recover leaves a note draft when materialization never happened (crash before file)" do
    {_repo, run} = setup_run("n5")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())

    work =
      Path.join(
        System.tmp_dir!(),
        "la_notes_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    assert {:ok, draft} = Notes.recover(note, work)
    assert draft.status == "draft"
    File.rm_rf!(work)
  end

  test "recover promotes a materialized file with matching hash back to published" do
    {_repo, run} = setup_run("n6")
    {:ok, note} = Notes.create(run.id, run.repository_id, note_body())

    work =
      Path.join(
        System.tmp_dir!(),
        "cd_notes_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    {:ok, _} = Notes.publish(note, work)
    broken = Repo.get!(LearningAgent.LearningNote, note.id)

    {:ok, _} =
      Repo.update(
        Ecto.Changeset.change(broken, status: "draft", file_path: nil, file_digest: nil)
      )

    {:ok, recovered} = Notes.recover(Repo.get!(LearningAgent.LearningNote, note.id), work)
    assert recovered.status == "published"
    File.rm_rf!(work)
  end
end

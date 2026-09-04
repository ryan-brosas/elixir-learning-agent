defmodule LearningAgent.Foundations do
  @moduledoc """
  Event-sourced foundation context.

  Pass observations and accepted capsules are immutable facts. The active
  `<slug>-foundation` directory is a complete, rebuildable projection of accepted
  capsules for exactly one repository pin.
  """
  import Ecto.Query

  alias LearningAgent.{
    ArtifactSet,
    FoundationCapsule,
    OutboxContext,
    PassObservation,
    Repo,
    Repository,
    RepositoryPin,
    Run
  }

  alias LearningAgent.Artifacts.{Manifest, Paths, Publisher}
  alias LearningAgent.Foundations.Projection
  alias LearningAgent.Skills.Root

  @context_capsules 24
  @context_items 100
  @context_bytes 8_192

  def record_observation(attrs) when is_map(attrs) do
    case Repo.get_by(PassObservation, run_id: Map.fetch!(attrs, :run_id)) do
      nil ->
        %PassObservation{} |> PassObservation.changeset(attrs) |> Repo.insert()

      existing ->
        if same_observation?(existing, attrs),
          do: {:ok, existing},
          else: {:error, :observation_conflict}
    end
  end

  @doc "Accept every directly evidenced seam in an observation; zero seams is valid."
  def accept_observed_seams(%PassObservation{} = observation) do
    observation.direct_evidence
    |> evidence_items()
    |> Enum.reduce_while({:ok, []}, fn evidence, {:ok, capsules} ->
      case accept_evidence(observation, evidence) do
        {:ok, capsule} -> {:cont, {:ok, [capsule | capsules]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, capsules} -> {:ok, Enum.reverse(capsules)}
      error -> error
    end
  end

  @doc "Compatibility wrapper returning the first accepted seam, if any."
  def accept_observed_seam(%PassObservation{} = observation) do
    case accept_observed_seams(observation) do
      {:ok, [capsule | _]} -> {:ok, capsule}
      {:ok, []} -> {:ok, nil}
      error -> error
    end
  end

  defp evidence_items(%{"seams" => seams}) when is_list(seams),
    do: Enum.filter(seams, &is_map/1)

  defp evidence_items(%{} = evidence) do
    if present?(Map.get(evidence, "source_path")) and present?(Map.get(evidence, "excerpt")),
      do: [evidence],
      else: []
  end

  defp evidence_items(_), do: []

  defp accept_evidence(observation, evidence) do
    path = Map.fetch!(evidence, "source_path")
    excerpt = Map.fetch!(evidence, "excerpt")

    attrs = %{
      repository_id: observation.repository_id,
      pin_id: observation.pin_id,
      observation_id: observation.id,
      stable_key: Projection.stable_key(path),
      source_path: path,
      source_excerpt: excerpt,
      source_digest: Map.get(evidence, "digest"),
      source_revision: Map.get(evidence, "revision"),
      test_evidence: Map.get(evidence, "test_evidence"),
      test_caveat: Map.get(evidence, "test_caveat"),
      question: Map.get(evidence, "question", "What stable behavior is exposed at `#{path}`?"),
      boundary:
        Map.get(evidence, "boundary", "The source unit at `#{path}` and its direct callers."),
      invariant:
        Map.get(
          evidence,
          "invariant",
          "The recorded source excerpt remains the authority for this seam."
        ),
      limits:
        Map.get(
          evidence,
          "limits",
          "Claims do not extend beyond the excerpt, pin, and recorded test binding."
        ),
      status: "accepted"
    }

    insert_capsule(attrs)
  end

  def accepted_capsules(repository_id, pin_id) do
    from(c in FoundationCapsule,
      where: c.repository_id == ^repository_id and c.pin_id == ^pin_id and c.status == "accepted",
      order_by: c.stable_key
    )
    |> Repo.all()
  end

  def observed?(repository_id, pin_id) do
    Repo.exists?(
      from(o in PassObservation,
        where: o.repository_id == ^repository_id and o.pin_id == ^pin_id
      )
    )
  end

  def covered_paths(repository_id, pin_id) do
    from(o in PassObservation,
      where: o.repository_id == ^repository_id and o.pin_id == ^pin_id,
      select: o.source_paths
    )
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc "Bounded current-pin context; learning-note bodies are never queried or injected."
  def prior_context(repository_id, pin_id) do
    capsules = accepted_capsules(repository_id, pin_id) |> Enum.take(@context_capsules)

    observations =
      from(o in PassObservation,
        where: o.repository_id == ^repository_id and o.pin_id == ^pin_id,
        order_by: [desc: o.pass_number],
        limit: 20
      )
      |> Repo.all()

    context = %{
      seams:
        Enum.map(capsules, fn c ->
          %{key: c.stable_key, path: c.source_path, question: c.question, invariant: c.invariant}
        end),
      coverage: covered_paths(repository_id, pin_id) |> Enum.take(@context_items),
      unresolved:
        observations |> Enum.flat_map(& &1.unresolved) |> Enum.uniq() |> Enum.take(@context_items),
      omissions:
        observations |> Enum.flat_map(& &1.omissions) |> Enum.uniq() |> Enum.take(@context_items)
    }

    text = context |> Jason.encode!() |> truncate_context()
    Map.put(context, :text, text)
  end

  def project(%Repository{} = repository, %Run{} = run, note) do
    capsules = accepted_capsules(repository.id, run.pin_id)

    with {:ok, files} <- Projection.files(repository, capsules) do
      manifest = Manifest.build(files)

      case active_artifact(repository.id, run.pin_id, manifest.manifest_digest) do
        %ArtifactSet{} = artifact ->
          link_run_and_repository(run, repository, artifact)
          {:ok, projection_result(artifact, true)}

        nil ->
          publish_new(repository, run, note, files, manifest)
      end
    end
  end

  def recover_artifacts do
    case Repo.query("SELECT to_regclass('public.pass_observations')") do
      {:ok, %{rows: [[nil]]}} -> :ok
      {:ok, _} -> recover_staged_artifacts()
      {:error, _} -> :ok
    end
  end

  defp recover_staged_artifacts do
    from(a in ArtifactSet,
      where:
        a.state == "staged" and not is_nil(a.repository_id) and not is_nil(a.pin_id) and
          a.producer == ^Publisher.producer(),
      order_by: a.inserted_at
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn artifact, :ok ->
      repository = Repo.get(Repository, artifact.repository_id)

      result =
        case Publisher.recover_foundation(Root.path(), repository.slug, artifact.manifest_digest) do
          {:ok, published} ->
            activate_recovered(artifact, repository, published.active)

          {:error, :generation_missing} ->
            rebuild_staged(artifact, repository)

          {:error, reason} ->
            {:error, reason}
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp rebuild_staged(artifact, repository) do
    with {:ok, files} <-
           Projection.files(repository, accepted_capsules(repository.id, artifact.pin_id)),
         manifest = Manifest.build(files),
         true <- manifest.manifest_digest == artifact.manifest_digest,
         {:ok, published} <- Publisher.publish_foundation(Root.path(), repository.slug, files) do
      activate_recovered(artifact, repository, published.active)
    else
      false -> {:error, :manifest_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate_recovered(artifact, repository, active_path) do
    case activate_artifact(artifact, repository, Repo.get(Run, artifact.run_id), active_path) do
      {:ok, _artifact} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish_new(repository, run, note, files, manifest) do
    generation = next_generation(repository.id)

    attrs = %{
      run_id: run.id,
      learning_note_id: note.id,
      repository_id: repository.id,
      pin_id: run.pin_id,
      generation: generation,
      manifest_digest: manifest.manifest_digest,
      state: "staged",
      producer: Publisher.producer(),
      projection_version: Projection.version()
    }

    with {:ok, artifact} <- %ArtifactSet{} |> ArtifactSet.changeset(attrs) |> Repo.insert(),
         {:ok, published} <- Publisher.publish_foundation(Root.path(), repository.slug, files),
         {:ok, artifact} <- activate_artifact(artifact, repository, run, published.active) do
      {:ok, projection_result(artifact, published.unchanged)}
    end
  end

  defp activate_artifact(artifact, repository, run, active_path) do
    Repo.transaction(fn ->
      artifact =
        artifact
        |> ArtifactSet.changeset(%{
          state: "active",
          active_path: active_path,
          staging_path: nil
        })
        |> Repo.update!()

      repository
      |> Ecto.Changeset.change(active_pin_id: artifact.pin_id, active_generation_id: artifact.id)
      |> Repo.update!()

      if run do
        run |> Ecto.Changeset.change(artifact_set_id: artifact.id) |> Repo.update!()
      end

      append_materialization!(artifact, repository, run)
      artifact
    end)
  end

  defp append_materialization!(artifact, repository, run) do
    pin = Repo.get!(RepositoryPin, artifact.pin_id)
    {:ok, paths} = Paths.foundation(Root.path(), repository.slug, artifact.manifest_digest)

    attrs = %{
      repository_id: repository.id,
      run_id: if(run, do: run.id, else: artifact.run_id),
      idempotency_key: "foundation:#{repository.id}:#{artifact.manifest_digest}",
      event_type: "materialize_foundation",
      destination: "foundations/#{repository.slug}/#{artifact.manifest_digest}",
      payload: %{
        "path" => paths.generation,
        "manifest_digest" => artifact.manifest_digest,
        "producer" => Publisher.producer(),
        "projection_version" => Projection.version(),
        "repository_id" => repository.id,
        "pin_id" => pin.id,
        "source_revision" => pin.commit_sha || pin.graph_generation || "unpinned",
        "authority" => false,
        "current_memory" => false
      }
    }

    case OutboxContext.append_idempotent(attrs) do
      {:ok, _event} -> :ok
      {:error, changeset} -> Repo.rollback({:outbox_invalid, changeset})
    end
  end

  defp link_run_and_repository(run, repository, artifact) do
    Repo.transaction(fn ->
      run |> Ecto.Changeset.change(artifact_set_id: artifact.id) |> Repo.update!()

      repository
      |> Ecto.Changeset.change(active_pin_id: artifact.pin_id, active_generation_id: artifact.id)
      |> Repo.update!()
    end)
  end

  defp active_artifact(repository_id, pin_id, digest) do
    Repo.one(
      from(a in ArtifactSet,
        where:
          a.repository_id == ^repository_id and a.pin_id == ^pin_id and
            a.manifest_digest == ^digest and
            a.state == "active",
        order_by: [desc: a.generation],
        limit: 1
      )
    )
  end

  defp next_generation(repository_id) do
    (Repo.one(
       from(a in ArtifactSet, where: a.repository_id == ^repository_id, select: max(a.generation))
     ) || 0) + 1
  end

  defp insert_capsule(attrs) do
    case Repo.get_by(FoundationCapsule,
           repository_id: attrs.repository_id,
           pin_id: attrs.pin_id,
           stable_key: attrs.stable_key
         ) do
      nil ->
        %FoundationCapsule{} |> FoundationCapsule.changeset(attrs) |> Repo.insert()

      existing ->
        if same_capsule?(existing, attrs), do: {:ok, existing}, else: {:error, :capsule_conflict}
    end
  end

  defp same_observation?(existing, attrs) do
    Enum.all?(
      [
        :repository_id,
        :run_id,
        :pin_id,
        :pass_number,
        :source_paths,
        :direct_evidence,
        :model,
        :coverage,
        :unresolved,
        :omissions
      ],
      &(Map.get(existing, &1) == Map.get(attrs, &1))
    )
  end

  defp same_capsule?(existing, attrs) do
    Enum.all?(
      [
        :repository_id,
        :pin_id,
        :stable_key,
        :source_path,
        :source_excerpt,
        :source_digest,
        :source_revision,
        :test_evidence,
        :test_caveat,
        :question,
        :boundary,
        :invariant,
        :limits
      ],
      &(Map.get(existing, &1) == Map.get(attrs, &1))
    )
  end

  defp projection_result(artifact, unchanged) do
    %{
      artifact: artifact,
      active: artifact.active_path,
      manifest_digest: artifact.manifest_digest,
      unchanged: unchanged
    }
  end

  defp truncate_context(text) when byte_size(text) <= @context_bytes, do: text

  defp truncate_context(text) do
    prefix = binary_part(text, 0, @context_bytes - byte_size("…"))
    valid_prefix(prefix) <> "…"
  end

  defp valid_prefix(prefix) do
    if String.valid?(prefix),
      do: prefix,
      else: valid_prefix(binary_part(prefix, 0, byte_size(prefix) - 1))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

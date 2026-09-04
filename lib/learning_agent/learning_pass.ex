defmodule LearningAgent.LearningPass do
  @moduledoc """
  One automatic repository-pin → immutable observation → accepted seam →
  complete `<slug>-foundation` projection pass.

  Automatic execution emits foundations only. Procedure promotion is a separate
  future operator boundary and is never available to this worker.
  """
  require Logger

  alias LearningAgent.{
    Activity,
    Foundations,
    LeaseContext,
    ModelGateway,
    ModelRetry,
    Notes,
    Repo,
    RepositoryContext,
    RepositoryPin,
    RunContext,
    SourceReader
  }

  alias LearningAgent.Domain.Run, as: RunDomain
  alias LearningAgent.Providers.OpenAICompatible
  alias LearningAgent.Skills.Root

  @skip_dirs MapSet.new(["node_modules", "deps", "_build", "dist", "target", "cover", "vendor"])
  @source_exts MapSet.new([".ex", ".exs", ".md", ".py", ".ts", ".js", ".rs", ".go", ".json"])
  @inventory_max_files 2_000
  @grounding_max_bytes 2 * 1_024
  @evidence_max_bytes 8 * 1_024
  @learn_max_bytes 24 * 1_024
  @learn_read_lines 400
  @learn_max_tokens 2_048
  @learn_max_prompt_bytes 24_000
  @component_study_files 8
  @component_file_bytes 8 * 1_024
  @component_file_lines 160

  def abort(run, reason), do: fail(run, reason)

  def execute(run, model \\ nil) do
    repository = RepositoryContext.get(run.repository_id) || {:error, :not_found}

    if match?(%LearningAgent.Repository{}, repository) do
      Activity.log(
        :info,
        "foundation pass started `#{repository.slug}` pass #{run.pass_number}" <> model_tag(model),
        %{
          repo: repository.slug,
          pass: run.pass_number,
          phase: "observation"
        }
      )
    end

    with %LearningAgent.Repository{} = repository <- repository,
         %RepositoryPin{} = pin <- Repo.get(RepositoryPin, run.pin_id),
         {:ok, run} <- step(run, "claimed", "preflight"),
         {:ok, observation} <- observe(repository, run, pin, model),
         {:ok, recorded} <-
           Foundations.record_observation(observation_attrs(repository, run, observation, model)),
         {:ok, run} <- step(run, "preflight", "note_drafting"),
         {:ok, note} <-
           Notes.create(run.id, repository.id, note_body(repository, run, observation, model)),
         {:ok, published_note} <- Notes.publish(note, notes_root()),
         {:ok, _capsules} <- Foundations.accept_observed_seams(recorded),
         {:ok, run} <- step(run, "note_drafting", "note_published"),
         {:ok, run} <- step(run, "note_published", "exploring"),
         {:ok, run} <- step(run, "exploring", "evidence_gathering"),
         {:ok, run} <- step(run, "evidence_gathering", "synthesizing"),
         {:ok, run} <- step(run, "synthesizing", "validating"),
         {:ok, projection} <- Foundations.project(repository, run, published_note),
         {:ok, run} <- step(run, "validating", "publishing"),
         {:ok, run} <- step(run, "publishing", "recording_result"),
         {:ok, run} <-
           step(run, "recording_result", "completed", %{finished_at: DateTime.utc_now()}) do
      release(run, "completed")
      maybe_requeue(repository, run)

      Activity.log(
        :ok,
        "foundation pass completed `#{repository.slug}` pass #{run.pass_number} · projection active",
        %{
          repo: repository.slug,
          pass: run.pass_number,
          foundation_projection_id: projection.artifact.id,
          manifest_digest: projection.manifest_digest,
          unchanged: projection.unchanged
        }
      )

      {:ok,
       %{
         run: run,
         foundation_projection: projection.active,
         foundation: projection.active,
         foundation_projection_id: projection.artifact.id,
         manifest_digest: projection.manifest_digest,
         unchanged: projection.unchanged,
         note: published_note.file_path
       }}
    else
      {:error, reason} = error ->
        fail(run, reason)
        error

      nil ->
        fail(run, :pin_not_found)
        {:error, :pin_not_found}
    end
  end

  def drained?(repository) do
    case RepositoryContext.current_pin(repository) do
      %RepositoryPin{id: pin_id} ->
        items = inventory(repository)

        (items != [] and uncovered_files(repository, pin_id) == []) or
          (items == [] and Foundations.observed?(repository.id, pin_id))

      _ ->
        false
    end
  end

  def uncovered_files(repository) do
    case RepositoryContext.current_pin(repository) do
      %RepositoryPin{id: pin_id} -> uncovered_files(repository, pin_id)
      _ -> inventory(repository)
    end
  end

  defp uncovered_files(repository, pin_id) do
    covered = Foundations.covered_paths(repository.id, pin_id) |> MapSet.new()
    Enum.reject(inventory(repository), &MapSet.member?(covered, &1))
  end

  defp observe(repository, run, pin, model) do
    remaining = uncovered_files(repository, pin.id)
    selected = List.first(remaining)
    direct_evidence = direct_evidence(repository, selected, pin)

    {:ok,
     %{
       files: remaining,
       memory: memory_blurb(repository.graph_project),
       architecture: architecture_grounding(repository.graph_project),
       component: component_of(selected),
       selected: selected,
       remaining: max(length(remaining) - 1, 0),
       prior: %{note: nil, count: run.pass_number - 1},
       context: Foundations.prior_context(repository.id, pin.id),
       direct_evidence: direct_evidence,
       pin: pin,
       model: model
     }}
  end

  defp observation_attrs(repository, run, observation, model) do
    source_paths = if is_binary(observation.selected), do: [observation.selected], else: []

    %{
      repository_id: repository.id,
      run_id: run.id,
      pin_id: run.pin_id,
      pass_number: run.pass_number,
      source_paths: source_paths,
      direct_evidence: observation.direct_evidence,
      model: observation_model(model),
      coverage: %{"selected" => observation.selected, "remaining" => observation.remaining},
      unresolved: observation.files |> Enum.drop(1) |> Enum.take(100),
      omissions: [],
      observed_at: DateTime.utc_now()
    }
  end

  defp observation_model(model) when is_binary(model) and model != "", do: model

  defp observation_model(_model) do
    case ModelGateway.connection() do
      %{enabled: true, model: model} when is_binary(model) and model != "" -> model
      _ -> nil
    end
  end

  defp direct_evidence(_repository, nil, _pin), do: %{}

  defp direct_evidence(repository, selected, pin) do
    with {:ok, absolute} <- SourceReader.resolve(repository.source_locator, selected),
         {:ok, material} <- study_material(absolute) do
      excerpt =
        material.content |> SourceReader.sanitize_utf8() |> String.slice(0, @evidence_max_bytes)

      revision = pin.commit_sha || pin.graph_generation || "unpinned"
      test_path? = Regex.match?(~r/(^|\/)(test|tests|spec)(\/|_)|_test\.|\.spec\./i, selected)

      %{
        "source_path" => selected,
        "excerpt" => excerpt,
        "digest" => Notes.digest(excerpt),
        "revision" => revision,
        "test_evidence" =>
          if(test_path?, do: "Direct test source excerpt from `#{selected}`", else: nil),
        "test_caveat" =>
          if(test_path?,
            do: nil,
            else:
              "No direct test was observed in this pass; behavior is bounded to the source excerpt"
          ),
        "question" => "What stable behavior is exposed by `#{selected}`?",
        "boundary" => "The source unit `#{selected}` at repository pin `#{revision}`.",
        "invariant" =>
          "Claims must remain consistent with the recorded source excerpt and digest.",
        "limits" => "No behavior outside this source unit or unobserved tests is implied."
      }
    else
      _ -> %{}
    end
  end

  defp note_body(repository, run, observation, model) do
    case learn(repository, run, observation, model) do
      {:ok, text} ->
        header =
          "Repository `#{repository.slug}` at pin `#{observation.pin.commit_sha || "unpinned"}`, " <>
            "pass #{run.pass_number}.\n#{observation.memory}#{model_line(model)}\n"

        text |> ensure_covered(observation.selected) |> prepend_architecture_intro(header)

      :fallback ->
        template_note(repository, run, observation)
    end
  end

  defp template_note(repository, run, observation) do
    covered =
      if observation.selected, do: "- `#{observation.selected}`", else: "- (no source observed)"

    partial =
      observation.files
      |> Enum.drop(if(observation.selected, do: 1, else: 0))
      |> Enum.take(50)
      |> case do
        [] -> "No unread source items remain."
        paths -> Enum.map_join(paths, "\n", &"- `#{&1}`")
      end

    selected = observation.selected || "none"

    """
    # architecture
    Repository `#{repository.slug}` at pin `#{observation.pin.commit_sha || "unpinned"}`, pass #{run.pass_number}.
    #{observation.memory}

    # covered
    #{covered}

    # partial/uncited
    #{partial}

    # porter-questions
    What stable seam, if any, is supported by direct evidence from `#{selected}`?

    # selected-subsystem
    #{selected}
    """
  end

  @doc "Generate one pass work record from direct evidence plus bounded current-pin projection context."
  def learn(repository, run, observation, model) do
    with %{} = connection <- ModelGateway.connection(),
         true <- connection.enabled and is_binary(connection.base_url),
         model_id = model || connection.model,
         true <- is_binary(model_id) and model_id != "",
         {:ok, file} <- learning_material(repository, observation) do
      complete =
        Application.get_env(:learning_agent, :note_complete, &OpenAICompatible.complete/1)

      retry = [max_attempts: min(ModelRetry.limit(), 30), sleep: &ModelRetry.backoff/1]

      prompt =
        learn_prompt(repository, run, observation, file)
        |> SourceReader.sanitize_utf8()
        |> String.slice(0, @learn_max_prompt_bytes)

      payload = %{
        model: model_id,
        messages: [%{role: :user, content: [%{type: :text, text: prompt}]}],
        base_url: connection.base_url,
        api_key: connection.api_key,
        timeout_ms: connection.timeout_ms || 15_000,
        max_tokens: @learn_max_tokens
      }

      case ModelRetry.call(fn -> complete.(payload) end, retry) do
        {:ok, %{text: text}} when is_binary(text) and byte_size(text) <= @learn_max_bytes ->
          if Notes.Validator.validate(text) == :ok, do: {:ok, text}, else: :fallback

        _ ->
          :fallback
      end
    else
      _ -> :fallback
    end
  end

  defp learning_material(_repository, %{direct_evidence: %{"excerpt" => excerpt}})
       when is_binary(excerpt) do
    {:ok, %{content: excerpt, truncated: byte_size(excerpt) >= @evidence_max_bytes}}
  end

  defp learning_material(repository, observation) do
    with selected when is_binary(selected) <- observation.selected,
         {:ok, absolute} <- SourceReader.resolve(repository.source_locator, selected) do
      study_material(absolute)
    else
      _ -> {:error, :no_source}
    end
  end

  defp learn_prompt(repository, run, observation, file) do
    context =
      get_in(observation, [:context, :text]) ||
        "{\"seams\":[],\"coverage\":[],\"unresolved\":[],\"omissions\":[]}"

    """
    You are recording one immutable observation for repository `#{repository.slug}`.
    This is pass #{run.pass_number}. Do not produce a procedure or a cumulative note.
    Keep exactly these five markdown sections: # architecture, # covered,
    # partial/uncited, # porter-questions, # selected-subsystem.
    State only what the provided source shows. Preserve unresolved uncertainty.
    Describe WHAT it does, WHO uses it and what it calls, WHERE it sits in the flow,
    WHEN it runs, and HOW it works, without extending beyond direct evidence.

    #{architecture_line(observation)}Memory from previous passes (bounded current-pin seams, coverage, unresolved items, and omissions only):
    #{context}

    This pass studies `#{observation.selected}`#{component_line(observation)} (truncated: #{file.truncated}):
    #{file.content}

    Return this pass's observation record with all five sections.
    """
  end

  defp study_material(absolute) do
    if File.dir?(absolute),
      do: component_material(absolute),
      else: SourceReader.read(absolute, 1, @learn_read_lines, max_bytes: @learn_max_bytes)
  end

  defp component_material(directory) do
    parts =
      directory
      |> component_files()
      |> Enum.map(fn absolute ->
        case SourceReader.read(absolute, 1, @component_file_lines,
               max_bytes: @component_file_bytes
             ) do
          {:ok, file} -> "## #{Path.relative_to(absolute, directory)}\n#{file.content}"
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if parts == [],
      do: {:error, {:read_error, :empty_component}},
      else: {:ok, %{content: Enum.join(parts, "\n\n"), truncated: false}}
  end

  defp component_files(directory) do
    directory
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort_by(fn path ->
      case File.stat(path) do
        {:ok, stat} -> -stat.size
        _ -> 0
      end
    end)
    |> Enum.take(@component_study_files)
  end

  defp inventory(repository), do: list_source(repository.source_locator)

  defp list_source(path) when is_binary(path) do
    root = Path.expand(path)

    if source_allowed?(root) and File.dir?(root) do
      components = component_keys(root)
      files = walk_source(root, root, [], @inventory_max_files) |> Enum.reverse() |> Enum.sort()
      Enum.uniq(components ++ files)
    else
      []
    end
  end

  defp list_source(_), do: []

  defp component_keys(root) do
    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reject(&(String.starts_with?(&1, ".") or MapSet.member?(@skip_dirs, &1)))
        |> Enum.filter(&File.dir?(Path.join(root, &1)))
        |> Enum.map(&(&1 <> "/"))

      _ ->
        []
    end
  end

  defp walk_source(_root, _directory, accumulator, max) when length(accumulator) >= max,
    do: accumulator

  defp walk_source(root, directory, accumulator, max) do
    case File.ls(directory) do
      {:ok, names} ->
        Enum.reduce(names, accumulator, fn name, acc ->
          path = Path.join(directory, name)

          cond do
            length(acc) >= max ->
              acc

            String.starts_with?(name, ".") or MapSet.member?(@skip_dirs, name) ->
              acc

            File.dir?(path) ->
              walk_source(root, path, acc, max)

            File.regular?(path) and
                MapSet.member?(@source_exts, String.downcase(Path.extname(name))) ->
              [Path.relative_to(path, root) | acc]

            true ->
              acc
          end
        end)

      _ ->
        accumulator
    end
  end

  defp source_allowed?(absolute) do
    configured =
      Application.get_env(:learning_agent, :source_root, "sources")
      |> List.wrap()
      |> Kernel.++(["/sources", "sources"])
      |> Enum.map(&Path.expand/1)
      |> Enum.any?(fn root -> absolute == root or String.starts_with?(absolute, root <> "/") end)

    configured or (not String.contains?(absolute, "..") and File.dir?(absolute))
  end

  defp memory_blurb(project) do
    case LearningAgent.MCP.Bridge.pin_status(project) do
      {:ok, pin} ->
        "Codebase Memory project `#{project}` status=#{pin.status} root=#{pin.root || "unknown"}."

      {:error, reason} ->
        "Codebase Memory is optional and unavailable: #{inspect(reason)}."
    end
  end

  defp architecture_grounding(project) do
    case LearningAgent.MCP.Bridge.architecture(project) do
      {:ok, value} -> value |> grounding_text() |> String.slice(0, @grounding_max_bytes)
      _ -> nil
    end
  end

  defp grounding_text(value) when is_binary(value), do: value

  defp grounding_text(%{"content" => content}) when is_list(content),
    do: Enum.map_join(content, "\n", &Map.get(&1, "text", ""))

  defp grounding_text(%{"summary" => summary}) when is_binary(summary), do: summary
  defp grounding_text(_), do: ""

  defp architecture_line(%{architecture: text}) when is_binary(text),
    do: "Codebase Memory architecture grounding:\n#{text}\n\n"

  defp architecture_line(_), do: ""

  defp component_line(%{component: component}) when is_binary(component),
    do: " (component #{component})"

  defp component_line(_), do: ""

  defp component_of(selected) when is_binary(selected) do
    case String.split(selected, "/", parts: 2) do
      [component, _] -> component <> "/"
      _ -> nil
    end
  end

  defp component_of(_), do: nil

  defp ensure_covered(text, selected) when is_binary(selected) do
    if String.contains?(covered_section(text) || "", "`#{selected}`"),
      do: text,
      else: String.replace(text, "# covered\n", "# covered\n- `#{selected}`\n", global: false)
  end

  defp ensure_covered(text, _), do: text

  defp covered_section(text) do
    case Regex.run(~r/# covered\n(.*?)(?:\n# |\z)/s, text) do
      [_, body] -> body
      _ -> nil
    end
  end

  defp prepend_architecture_intro(text, header) do
    case String.split(text, "# architecture\n", parts: 2) do
      [before, rest] -> before <> "# architecture\n" <> header <> rest
      _ -> text
    end
  end

  defp maybe_requeue(repository, run) do
    current = RepositoryContext.get(repository.id) || repository
    remaining = uncovered_files(current, run.pin_id)
    max = Application.get_env(:learning_agent, :max_auto_passes, 0)

    cond do
      current.status == "disabled" ->
        :ok

      remaining == [] ->
        RepositoryContext.set_status(current.id, "complete") && :ok

      is_integer(max) and max > 0 and run.pass_number >= max ->
        RepositoryContext.set_status(current.id, "complete") && :ok

      true ->
        safe_pass_requeue(current.id)
    end
  end

  defp safe_pass_requeue(repository_id) do
    try do
      case RepositoryContext.queue_pass(repository_id) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    rescue
      Postgrex.Error -> :ok
    end
  end

  defp step(run, from, to, attrs \\ %{}) do
    current = RunContext.get(run.id) || run

    if RunContext.cancelled?(current) do
      _ =
        RunContext.transition(run.id, from, "cancelled", run.lease_epoch, %{
          finished_at: DateTime.utc_now()
        })

      {:error, :cancelled}
    else
      RunContext.transition(run.id, from, to, run.lease_epoch, attrs)
    end
  end

  defp notes_root do
    Path.join(Root.path(), "_notes")
  end

  defp fail(run, reason) do
    Logger.error("foundation_pass_failed run=#{run.id} reason=#{inspect(reason)}")
    current = RunContext.get(run.id) || run
    from_atom = String.to_existing_atom(to_string(current.state))

    to =
      cond do
        RunDomain.valid_transition?(from_atom, :failed) -> "failed"
        RunDomain.valid_transition?(from_atom, :cancelled) -> "cancelled"
        true -> nil
      end

    if to do
      _ =
        RunContext.transition(
          current.id,
          current.state,
          to,
          current.lease_epoch || run.lease_epoch,
          %{
            finished_at: DateTime.utc_now(),
            failure_class: failure_class(reason),
            blocked_reason: reason_text(reason)
          }
        )
    end

    release(current, "failed")
  end

  defp release(run, outcome) do
    case LeaseContext.release_for(
           run.repository_id,
           run.lease_epoch,
           RunContext.holder(),
           outcome
         ) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp failure_class(:not_writable), do: "not_writable"
  defp failure_class(:eacces), do: "not_writable"
  defp failure_class(:artifact_conflict), do: "artifact_conflict"
  defp failure_class(_), do: "error"
  defp reason_text(reason), do: reason |> inspect() |> String.slice(0, 240)
  defp model_tag(nil), do: ""
  defp model_tag(model), do: " · model #{model}"
  defp model_line(nil), do: ""
  defp model_line(""), do: ""
  defp model_line(model), do: "\nAssigned model `#{model}`."
end

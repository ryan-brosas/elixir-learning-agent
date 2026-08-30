defmodule LearningAgent.LearningPass do
  @moduledoc """
  One automatic learn → note → skill pass.

  Observes a registered repository (source listing, optional Codebase Memory),
  publishes a learning note first, then writes a foundation leaf under
  `.agents/skills/<slug>/`. The worker never writes outside that root.
  """
  require Logger

  alias LearningAgent.{
    Activity,
    ModelGateway,
    ModelRetry,
    Notes,
    LearningNote,
    Repo,
    RepositoryContext,
    RunContext,
    LeaseContext,
    OutboxContext,
    SourceReader
  }

  alias LearningAgent.Providers.OpenAICompatible

  import Ecto.Query

  @skip_dirs MapSet.new(["node_modules", "deps", "_build", "dist", "target", "cover", "vendor"])
  @source_exts MapSet.new([".ex", ".exs", ".md", ".py", ".ts", ".js", ".rs", ".go", ".json"])
  @grounding_max_bytes 2 * 1024
  # A 200-file walk cap let a 29k-file repo "drain" after 200 passes; breadth
  # still needs a bound, but 10x deeper before a repo can claim coverage.
  @inventory_max_files 2_000
  alias LearningAgent.Domain.Run, as: RunDomain
  alias LearningAgent.Skills.{Capsule, Leaf, Root, Store, Synthesizer}

  def abort(run, reason), do: fail(run, reason)

  def execute(run, model \\ nil) do
    repo = RepositoryContext.get(run.repository_id) || {:error, :not_found}

    case repo do
      %LearningAgent.Repository{} = r ->
        Activity.log(
          :info,
          "pass started `#{r.slug}` pass #{run.pass_number}" <> model_tag(model),
          %{
            repo: r.slug,
            pass: run.pass_number
          }
        )

      _ ->
        :ok
    end

    with %LearningAgent.Repository{} = repo <- repo,
         {:ok, run} <- step(run, "claimed", "preflight"),
         {:ok, observation} <- observe(repo),
         {:ok, run} <- step(run, "preflight", "note_drafting"),
         {:ok, note} <-
           Notes.create(run.id, repo.id, effective_body(repo, run, observation, model)),
         {:ok, published} <- Notes.publish(note, notes_root()),
         {:ok, run} <- step(run, "note_drafting", "note_published"),
         {:ok, run} <- step(run, "note_published", "exploring"),
         {:ok, run} <- step(run, "exploring", "evidence_gathering"),
         {:ok, run} <- step(run, "evidence_gathering", "synthesizing"),
         {:ok, files} <- synthesize(repo, run, observation, published),
         {:ok, run} <- step(run, "synthesizing", "validating"),
         {:ok, dest} <- Store.write_leaf(repo.slug, files),
         :ok <- enqueue_openviking(repo, run, published, dest),
         {:ok, run} <- step(run, "validating", "publishing"),
         {:ok, run} <- step(run, "publishing", "recording_result"),
         {:ok, run} <-
           step(run, "recording_result", "completed", %{finished_at: DateTime.utc_now()}) do
      release(run, "completed")
      maybe_requeue(repo, run)
      Logger.info("learning_pass_complete run=#{run.id} skill=#{dest}")

      Activity.log(
        :ok,
        "pass completed `#{repo.slug}` pass #{run.pass_number} · skill written",
        %{
          repo: repo.slug,
          pass: run.pass_number
        }
      )

      {:ok, %{run: run, skill: dest, note: published.file_path}}
    else
      {:error, reason} = err ->
        fail(run, reason)
        err
    end
  end

  def drained?(repo) do
    notes = note_bodies(repo.id)
    LearningAgent.Domain.Squeeze.closed?(inventory(repo), notes)
  end

  def uncovered_files(repo) do
    notes = note_bodies(repo.id)
    LearningAgent.Domain.Squeeze.uncovered(inventory(repo), notes)
  end

  defp model_tag(nil), do: ""
  defp model_tag(model), do: " · model " <> model

  defp repo_slug_for(run) do
    case RepositoryContext.get(run.repository_id) do
      %{} = r -> r.slug
      _ -> "unknown"
    end
  end

  defp class_of(%{class: c}), do: c
  defp class_of(_), do: :error

  defp model_line(nil), do: ""
  defp model_line(""), do: ""
  defp model_line(model), do: "\nAssigned model `" <> model <> "`."

  defp observe(repo) do
    remaining = uncovered_files(repo)
    selected = List.first(remaining)

    {:ok,
     %{
       files: remaining,
       memory: memory_blurb(repo.graph_project),
       architecture: architecture_grounding(repo.graph_project),
       component: component_of(selected),
       selected: selected || repo.slug,
       remaining: max(length(remaining) - 1, 0),
       prior: prior_memory(repo.id)
     }}
  end

  defp component_of(selected) when is_binary(selected) do
    case String.split(selected, "/", parts: 2) do
      [component, _rest] -> component <> "/"
      _ -> nil
    end
  end

  defp component_of(_), do: nil

  defp architecture_grounding(project) do
    case LearningAgent.MCP.Bridge.architecture(project) do
      {:ok, value} ->
        value
        |> grounding_text()
        |> String.slice(0, @grounding_max_bytes)

      _ ->
        nil
    end
  end

  defp grounding_text(value) when is_binary(value), do: value

  defp grounding_text(%{"content" => content}) when is_list(content) do
    content |> Enum.map(&Map.get(&1, "text", "")) |> Enum.join("\n")
  end

  defp grounding_text(%{"summary" => summary}) when is_binary(summary), do: summary
  defp grounding_text(_), do: ""

  # The note is the durable memory: the newest published note is fed back into
  # the next pass so learning is cumulative, never zero-context.
  defp prior_memory(repository_id) do
    latest =
      from(n in LearningNote,
        where: n.repository_id == ^repository_id and n.status == "published",
        order_by: [desc: n.inserted_at],
        limit: 1,
        select: n.content
      )
      |> Repo.one()

    count = length(note_bodies(repository_id))

    %{note: latest, count: count}
  end

  defp inventory(repo) do
    repo.source_locator
    |> list_source()
  end

  defp list_source(path) when is_binary(path) do
    root = Path.expand(path)

    if source_allowed?(root) and File.dir?(root) do
      components = component_keys(root)
      files = walk_source(root, root, [], @inventory_max_files) |> Enum.reverse() |> Enum.sort()

      if length(files) >= @inventory_max_files do
        require Logger

        Logger.warning(
          "source_inventory_truncated root=#{root} cap=#{@inventory_max_files} — coverage will not reach every file"
        )
      end

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

  defp walk_source(_root, _dir, acc, max) when length(acc) >= max, do: acc

  defp walk_source(root, dir, acc, max) do
    case File.ls(dir) do
      {:ok, names} ->
        Enum.reduce(names, acc, fn name, acc ->
          cond do
            length(acc) >= max ->
              acc

            String.starts_with?(name, ".") ->
              acc

            MapSet.member?(@skip_dirs, name) ->
              acc

            true ->
              path = Path.join(dir, name)

              cond do
                File.dir?(path) ->
                  walk_source(root, path, acc, max)

                File.regular?(path) and
                    MapSet.member?(@source_exts, String.downcase(Path.extname(name))) ->
                  [Path.relative_to(path, root) | acc]

                true ->
                  acc
              end
          end
        end)

      _ ->
        acc
    end
  end

  defp note_bodies(repository_id) do
    from(n in LearningNote, where: n.repository_id == ^repository_id, select: n.content)
    |> Repo.all()
  end

  defp source_allowed?(abs) do
    configured =
      Application.get_env(:learning_agent, :source_root, "sources")
      |> List.wrap()
      |> Kernel.++(["/sources", "sources"])
      |> Enum.map(&Path.expand/1)
      |> Enum.any?(fn root -> abs == root or String.starts_with?(abs, root <> "/") end)

    configured or (not String.contains?(abs, "..") and File.dir?(abs))
  end

  defp memory_blurb(project) do
    case LearningAgent.MCP.Bridge.pin_status(project) do
      {:ok, pin} ->
        "Codebase Memory project `#{project}` status=#{pin.status} root=#{pin.root || "unknown"}."

      {:error, reason} ->
        "Codebase Memory project `#{project}` is the navigation surface; live MCP was #{inspect(reason)}."
    end
  end

  @learn_max_bytes 24 * 1024
  @learn_read_lines 400
  @learn_max_tokens 2_048
  # top-tools-ai rejects prompts >= ~32KB with 429 (quota by payload size);
  # clamp the assembled prompt so every pass fits, and the retry ladder only
  # ever rides genuine transient 429s instead of structural ones.
  @learn_max_prompt_bytes 24_000
  @learn_prior_bytes 8 * 1024
  # Component passes study the component's own files, biggest first, instead of
  # failing on a directory read and faking coverage with a template note.
  @component_study_files 8
  @component_file_bytes 8 * 1024
  @component_file_lines 160

  defp note_body(repo, run, observation, model) do
    case learn(repo, run, observation, model) do
      {:ok, text} ->
        header =
          "Repository `#{repo.slug}` at `#{repo.source_locator}` (graph `#{repo.graph_project}`), " <>
            "pass #{run.pass_number}.\n#{observation.memory}#{model_line(model)}\n"

        text
        |> ensure_covered(observation.selected)
        |> prepend_architecture_intro(header)

      :fallback ->
        template_note(repo, run, observation, prior_body(repo))
    end
  end

  # A model failure must never erase prior knowledge: the fallback note
  # carries the previous note forward (memory accumulates across passes) and
  # only re-marks the current file as covered. The partial/uncited list is
  # bounded so it cannot crowd the next session's prompt with file names.
  defp template_note(repo, run, observation, prior) do
    covered =
      if observation.selected == nil do
        "- (no remaining unread files)"
      else
        "- `" <> observation.selected <> "`"
      end

    if is_binary(prior) and complete_sections?(prior) do
      prior
      |> ensure_covered(observation.selected)
      |> prepend_fallback_header(repo, run, covered)
    else
      fresh_template(repo, run, observation, covered)
    end
  end

  defp fresh_template(repo, run, observation, covered) do
    unread =
      observation.files
      |> List.wrap()
      |> Enum.reject(&(&1 == observation.selected))
      |> Enum.take(50)

    partial =
      if unread == [] do
        "No unread source files remain; this repository is drained."
      else
        Enum.map_join(unread, "
", &("- `" <> &1 <> "`"))
      end

    selected = observation.selected || repo.slug

    yes = """
    # architecture
    Repository `#{repo.slug}` at `#{repo.source_locator}` (graph `#{repo.graph_project}`), pass #{run.pass_number}.
    #{observation.memory}#{model_line(nil)}

    # covered
    #{covered}

    # partial/uncited
    #{partial}

    # porter-questions
    What is the first reusable seam to encode from `#{selected}`?

    # selected-subsystem
    #{selected}
    """

    yes
  end

  defp complete_sections?(content) do
    Enum.all?(
      ["architecture", "porter-questions", "selected-subsystem", "covered", "partial/uncited"],
      &String.contains?(String.downcase(content), &1)
    )
  end

  defp prepend_fallback_header(text, repo, run, covered) do
    header =
      "

> Fallback (no model output) pass #{run.pass_number} for `#{repo.slug}`: prior knowledge carried forward.

" <>
        "# covered
#{covered}

"

    text
    |> String.replace(
      "# covered
",
      header,
      global: false
    )
  end

  defp effective_body(repo, run, observation, model) do
    if observation.files == [] or observation.selected == repo.slug do
      # Nothing left to study (drained relearn): carry the prior published note
      # forward instead of clobbering real knowledge with an empty template.
      case prior_body(repo) do
        nil -> note_body(repo, run, observation, model)
        body -> body
      end
    else
      note_body(repo, run, observation, model)
    end
  end

  defp prior_body(repo) do
    from(n in LearningNote,
      where: n.repository_id == ^repo.id and n.status == "published",
      order_by: [desc: n.inserted_at],
      limit: 1,
      select: n.content
    )
    |> Repo.one()
  end

  @doc """
  One model turn that grows the whole note. Reads the selected source through
  SourceReader (bounded), feeds the previous note as memory, and returns the
  updated note. Any failure falls back to the deterministic template so the
  pass keeps its progress guarantees.
  """
  def learn(repo, run, observation, model) do
    with %{} = conn <- ModelGateway.connection(),
         true <- conn.enabled and is_binary(conn.base_url),
         model_id = model || conn.model,
         true <- is_binary(model_id) and model_id != "",
         {:ok, abs} <- SourceReader.resolve(repo.source_locator, observation.selected),
         {:ok, file} <- study_material(abs) do
      complete =
        Application.get_env(:learning_agent, :note_complete, &OpenAICompatible.complete/1)

      # Per-file cap: rate-limited providers need minutes of patience while
      # the quota window frees; non-429 failures still fall back fast.
      retry = [
        max_attempts: min(ModelRetry.limit(), 30),
        sleep: &ModelRetry.backoff/1
      ]

      prompt =
        learn_prompt(repo, run, observation, file)
        |> SourceReader.sanitize_utf8()
        |> String.slice(0, @learn_max_prompt_bytes)

      payload = %{
        model: model_id,
        messages: [
          %{
            role: :user,
            content: [%{type: :text, text: prompt}]
          }
        ],
        base_url: conn.base_url,
        api_key: conn.api_key,
        timeout_ms: conn.timeout_ms || 15_000,
        # Bound the note generation: an open-ended reasoning model can spin for
        # many minutes, blowing any client timeout and falling back to the
        # template. A capped completion finishes well inside the window.
        max_tokens: @learn_max_tokens
      }

      case ModelRetry.call(fn -> complete.(payload) end, retry) do
        {:ok, %{text: text}} when is_binary(text) and byte_size(text) <= @learn_max_bytes ->
          if Notes.Validator.validate(text) == :ok do
            Activity.log(:info, "model note grown via `#{model_id}` for `#{repo.slug}`", %{
              repo: repo.slug
            })

            {:ok, text}
          else
            Activity.log(
              :warn,
              "model note invalid (missing sections); using template for `#{repo.slug}`",
              %{repo: repo.slug}
            )

            :fallback
          end

        {:error, reason} ->
          Activity.log(
            :warn,
            "model call failed for `#{repo.slug}` (#{inspect(class_of(reason))}); using template",
            %{
              repo: repo.slug
            }
          )

          :fallback
      end
    else
      reason ->
        Logger.warning(
          "learning_learn_skipped repo=#{repo.slug} selected=#{inspect(observation.selected)} reason=#{inspect(reason)}"
        )

        :fallback
    end
  end

  # A selected component is a directory: study its own files (bounded) instead
  # of failing the read and faking coverage with a template note.
  defp study_material(abs) do
    if File.dir?(abs) do
      component_material(abs)
    else
      SourceReader.read(abs, 1, @learn_read_lines, max_bytes: @learn_max_bytes)
    end
  end

  defp component_material(dir) do
    parts =
      dir
      |> component_files()
      |> Enum.map(fn abs ->
        rel = Path.relative_to(abs, dir)

        case SourceReader.read(abs, 1, @component_file_lines, max_bytes: @component_file_bytes) do
          {:ok, file} -> "## " <> rel <> "\n" <> file.content
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if parts == [] do
      {:error, {:read_error, :empty_component}}
    else
      {:ok, %{content: Enum.join(parts, "\n\n"), truncated: false}}
    end
  end

  defp component_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?(&1))
    |> Enum.sort_by(&File.stat!(&1).size, :desc)
    |> Enum.take(@component_study_files)
  end

  defp architecture_line(%{architecture: nil}), do: ""

  defp architecture_line(%{architecture: text}) when is_binary(text),
    do: "Codebase Memory architecture grounding:\n" <> text <> "\n\n"

  defp architecture_line(_), do: ""

  defp component_line(%{component: component}) when is_binary(component),
    do: " (component " <> component <> ")"

  defp component_line(_), do: ""

  defp learn_prompt(repo, run, observation, file) do
    prior =
      case observation.prior && observation.prior.note do
        nil -> "(first pass - no prior note; start the memory)"
        note -> String.slice(note, 0, @learn_prior_bytes)
      end

    """
    You are the durable learner for repository `#{repo.slug}` (#{repo.source_locator}).
    You maintain ONE growing note across passes. This is pass #{run.pass_number}; #{observation.prior.count} note(s) exist.
    Hard rules:
    - Keep exactly these five markdown sections: # architecture, # covered, # partial/uncited, # porter-questions, # selected-subsystem.
    - # architecture ACCUMULATES durable structural facts across passes; never drop earlier facts unless this file corrects them.
    - # covered lists already-studied items, one `- \`path\`` per line.
    - # partial/uncited lists items not yet studied (one per line).
    - # porter-questions holds concrete porting questions; answer what this file resolves, add what it raises.
    - Only state what the provided source actually shows.

    Depth requirements for this pass (the note must read like an engineer wrote it, not a file index):
    - In # architecture, keep an accumulating component map: for the studied subsystem record what it does, why it exists, and who consumes it.
    - For the studied file capture the W's: WHAT it does (responsibility), WHO uses it and WHAT it calls (imports, entry points), WHERE it sits in the data flow, WHEN it runs (lifecycle/trigger), and HOW it works (key functions, state, gotchas).
    - # porter-questions must list the W's this pass answered and the concrete seams a port would reuse.

    #{architecture_line(observation)}Memory from previous passes:
    #{prior}

    This pass studies \`#{observation.selected}\`#{component_line(observation)} (truncated: #{file.truncated}):
    #{file.content}

    Return the complete updated note with all five sections.
    """
  end

  defp ensure_covered(text, selected) when is_binary(selected) and selected != "" do
    covered_block = covered_section(text)

    if covered_block && String.contains?(covered_block, "`" <> selected <> "`") do
      text
    else
      String.replace(text, "# covered\n", "# covered\n- `" <> selected <> "`\n", global: false)
    end
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

  defp synthesize(repo, run, observation, note) do
    seam = repo.slug <> "-pass-" <> Integer.to_string(run.pass_number)
    ref = Synthesizer.capsule_ref(seam)

    capsule =
      Capsule.new(%{
        seam: seam,
        question: "What did pass #{run.pass_number} observe in #{repo.slug}?",
        source: repo.source_locator,
        path_symbol: observation.selected,
        signature: "learning-pass/#{run.pass_number}",
        data_shape: "note + foundation leaf",
        decisive_source: note.file_path || "unpublished",
        flow: "observe -> note -> skill",
        invariant: "Skills write only under the locked skills root.",
        probe: "File.exists?(Path.join(skill_dir, \"SKILL.md\"))",
        verdict: "Pass #{run.pass_number} published a note-first leaf for `#{repo.slug}`."
      })

    skill = """
    ---
    name: #{repo.slug}
    description: #{skill_description(note, repo)}
    ---

    # #{repo.display_name} - what this codebase is and how it works

    #{skill_body(note, repo)}

    ## Loader
    #{Enum.join(Leaf.loader_lines([ref]), "\n")}

    ## Capsule map
    #{Enum.join(Leaf.map_lines([ref]), "\n")}
    """

    {:ok,
     %{
       "SKILL.md" => skill,
       ref => Synthesizer.render_capsule(capsule)
     }}
  end

  # The skill must carry the learned knowledge itself: the accumulated
  # architecture (component map, W's) and the open porting questions - not a
  # file index pointing at the note.
  # The skill distills KNOWLEDGE, not one pass: it merges the architecture
  # and porter content of the most recent learned notes so a SKILL.md stands
  # as the repo's accumulated memory, not a single-file stub. Identical
  # carry-forward fallbacks dedupe away.
  defp skill_body(_note, repo) do
    notes = recent_notes(repo, 8)
    sections = Enum.map(notes, &skill_content(&1))
    {archs, questions} = Enum.unzip(sections)

    arch =
      archs
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.join("\n\n---\n\n")

    qs =
      questions
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.join("\n\n")

    base =
      if qs == "" do
        arch
      else
        arch <> "\n\n## Open questions for a port\n\n" <> qs
      end

    String.trim_trailing(base)
  end

  defp recent_notes(repo, limit) do
    from(n in LearningNote,
      where: n.repository_id == ^repo.id and n.status == "published",
      order_by: [desc: n.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(& &1.content)
  end

  defp skill_content(content) do
    arch =
      case LearningAgent.Domain.Squeeze.section(content, "architecture") do
        body when is_binary(body) -> strip_architecture_headers(String.trim(body))
        _ -> ""
      end

    {
      arch,
      question_section(content)
    }
  end

  defp strip_architecture_headers(body) do
    body
    |> String.split("\n")
    |> Enum.reject(
      &(String.starts_with?(&1, "Repository \`") or
          String.contains?(&1, "Codebase Memory project"))
    )
    |> Enum.join("\n")
  end

  defp question_section(content) do
    case LearningAgent.Domain.Squeeze.section(content, "porter-questions") do
      body when is_binary(body) -> String.trim(body)
      _ -> ""
    end
  end

  defp skill_description(note, repo) do
    case LearningAgent.Domain.Squeeze.section(note.content, "architecture") do
      body when is_binary(body) ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.contains?(&1, "Repository `"))
        |> List.first("")
        |> String.slice(0, 160)
        |> case do
          "" -> "Learning notes for " <> repo.display_name
          line -> String.trim(line)
        end

      _ ->
        "Learning notes for " <> repo.display_name
    end
  end

  defp step(run, from, to, attrs \\ %{}) do
    current = RunContext.get(run.id) || run

    if RunContext.cancelled?(current) do
      RunContext.transition(run.id, from, "cancelled", run.lease_epoch, %{
        finished_at: DateTime.utc_now()
      })

      {:error, :cancelled}
    else
      RunContext.transition(run.id, from, to, run.lease_epoch, attrs)
    end
  end

  defp notes_root do
    case Root.contain("_notes") do
      {:ok, path} -> path
      _ -> Path.join(System.tmp_dir!(), "learning-agent-notes")
    end
  end

  defp fail(run, reason) do
    Logger.error("learning_pass_failed run=#{run.id} reason=#{inspect(reason)}")

    Activity.log(
      :error,
      "pass failed `#{repo_slug_for(run)}` pass #{run.pass_number}: #{reason_text(reason)}",
      %{
        repo: repo_slug_for(run)
      }
    )

    current = RunContext.get(run.id) || run
    from = current.state
    epoch = current.lease_epoch || run.lease_epoch
    class = failure_class(reason)

    from_atom = String.to_existing_atom(to_string(from))

    to =
      cond do
        RunDomain.valid_transition?(from_atom, :failed) -> "failed"
        RunDomain.valid_transition?(from_atom, :cancelled) -> "cancelled"
        true -> nil
      end

    if is_binary(to) do
      _ =
        RunContext.transition(current.id, from, to, epoch, %{
          finished_at: DateTime.utc_now(),
          failure_class: class,
          blocked_reason: reason_text(reason)
        })
    end

    release(current, "failed")
  end

  defp failure_class(:not_writable), do: "not_writable"
  defp failure_class(:eacces), do: "not_writable"

  defp failure_class({:exception, msg}) when is_binary(msg) do
    if String.contains?(msg, "permission denied"), do: "not_writable", else: "exception"
  end

  defp failure_class(_), do: "error"

  defp reason_text(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  defp reason_text(reason), do: reason |> inspect() |> String.slice(0, 240)

  defp release(run, outcome) do
    case LeaseContext.release_for(
           run.repository_id,
           run.lease_epoch,
           RunContext.holder(),
           outcome
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("lease_release_skipped run=#{run.id} reason=#{inspect(reason)}")
    end
  end

  defp enqueue_openviking(repo, run, note, dest) do
    _ =
      OutboxContext.append(%{
        repository_id: repo.id,
        run_id: run.id,
        idempotency_key: "note:" <> to_string(note.id),
        event_type: "add_learning_note",
        destination: "learning/" <> repo.slug,
        payload: %{"path" => note.file_path, "skill" => dest}
      })

    _ =
      OutboxContext.append(%{
        repository_id: repo.id,
        run_id: run.id,
        idempotency_key: "skill:" <> repo.slug <> ":" <> Integer.to_string(run.pass_number),
        event_type: "add_capsule",
        destination: "skills/" <> repo.slug,
        payload: %{"path" => dest}
      })

    :ok
  end

  defp maybe_requeue(repo, run) do
    current = RepositoryContext.get(repo.id) || repo
    remaining = uncovered_files(current)
    max = Application.get_env(:learning_agent, :max_auto_passes, 0)

    cond do
      current.status == "disabled" ->
        :ok

      remaining == [] ->
        _ = RepositoryContext.set_status(current.id, "complete")
        Logger.info("learning_repo_drained repo=#{current.slug} pass=#{run.pass_number}")

        Activity.log(:ok, "repo squeezed `#{current.slug}` — nothing left to learn", %{
          repo: current.slug
        })

        :ok

      is_integer(max) and max > 0 and run.pass_number >= max ->
        # The cap is a circuit breaker: settle the repo so self-heal stops
        # requeueing it (an active repo without queued work would hot-loop).
        _ = RepositoryContext.set_status(current.id, "complete")

        Logger.info("learning_pass_cap repo=#{current.slug} pass=#{run.pass_number}")

        Activity.log(
          :info,
          "pass cap reached \`#{current.slug}\` — settled to complete until an operator re-learns",
          %{repo: current.slug}
        )

        :ok

      true ->
        case RepositoryContext.queue_pass(current.id) do
          {:ok, next} ->
            Logger.info(
              "learning_pass_requeued repo=#{current.slug} pass=#{next.pass_number} remaining=#{length(remaining)}"
            )

            Activity.log(
              :info,
              "requeued `#{current.slug}` pass #{next.pass_number} · #{length(remaining)} source items left",
              %{repo: current.slug}
            )

            :ok

          {:error, reason} ->
            Logger.warning("learning_pass_requeue_skipped reason=#{inspect(reason)}")
        end
    end
  end
end

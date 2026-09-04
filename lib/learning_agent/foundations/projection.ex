defmodule LearningAgent.Foundations.Projection do
  @moduledoc "Pure, complete cold projection of all accepted capsules at one pin."

  alias LearningAgent.Artifacts.Publisher
  alias LearningAgent.Skills.{Capsule, Leaf, Synthesizer}

  @projection_version 1

  def version, do: @projection_version

  def stable_key(source_path) when is_binary(source_path) do
    stem =
      source_path
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 44)

    suffix =
      :crypto.hash(:sha256, source_path) |> Base.encode16(case: :lower) |> binary_part(0, 12)

    if(stem == "", do: "seam", else: stem) <> "-" <> suffix
  end

  def files(repository, capsules) when is_list(capsules) do
    capsules = Enum.sort_by(capsules, & &1.stable_key)
    refs = Enum.map(capsules, &Synthesizer.capsule_ref(&1.stable_key))

    files =
      capsules
      |> Map.new(fn accepted ->
        capsule = to_capsule(repository, accepted)
        {Synthesizer.capsule_ref(accepted.stable_key), Synthesizer.render_capsule(capsule)}
      end)
      |> Map.put("SKILL.md", skill(repository, refs))
      |> Map.put(Publisher.owner_file(), owner_marker(repository))

    with :ok <- validate_files(files) do
      {:ok, files}
    end
  end

  @doc "Mechanical guard: automatic generation can only emit a foundation leaf."
  def validate_files(files) do
    skill = Map.get(files, "SKILL.md", "")
    refs = files |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "references/"))
    loader = Leaf.refs_from_loader(skill)

    cond do
      not String.contains?(skill, "kind: foundation") ->
        {:error, :foundation_kind_missing}

      String.contains?(skill, "kind: procedure") ->
        {:error, :procedure_forbidden}

      not String.contains?(skill, "invocation: manual") ->
        {:error, :manual_invocation_missing}

      not String.contains?(skill, "disable-model-invocation: true") ->
        {:error, :model_invocation_not_disabled}

      Leaf.check_parity(loader, refs, refs) != :ok ->
        {:error, :projection_parity_failed}

      true ->
        :ok
    end
  end

  defp skill(repository, []) do
    header(repository) <>
      """

      # #{repository.display_name} foundation

      Cold, pin-scoped repository knowledge produced from accepted direct evidence.

      ## Loader
      No accepted seam capsules exist for the current pin.

      ## Capsule map
      No accepted seam capsules exist for the current pin.
      """
  end

  defp skill(repository, refs) do
    header(repository) <>
      """

      # #{repository.display_name} foundation

      Cold, pin-scoped repository knowledge produced from accepted direct evidence.

      ## Loader
      #{Enum.join(Leaf.loader_lines(refs), "\n")}

      ## Capsule map
      #{Enum.join(Leaf.map_lines(refs), "\n")}
      """
  end

  defp header(repository) do
    description =
      ("Stable direct-evidence foundation for " <> repository.display_name)
      |> yaml_string()

    """
    ---
    name: #{yaml_string(repository.slug <> "-foundation")}
    description: #{description}
    kind: foundation
    invocation: manual
    disable-model-invocation: true
    producer: elixir-learning-agent
    projection-version: 1
    ---
    """
    |> String.trim_trailing()
  end

  defp owner_marker(repository) do
    Jason.encode!(%{
      "kind" => "foundation",
      "producer" => Publisher.producer(),
      "projection_version" => @projection_version,
      "repository" => repository.slug
    })
  end

  defp to_capsule(repository, accepted) do
    Capsule.new(%{
      seam: accepted.stable_key,
      question: accepted.question,
      source: repository.slug,
      path_symbol: accepted.source_path,
      direct_source_excerpt: accepted.source_excerpt,
      source_digest: accepted.source_digest,
      source_revision: accepted.source_revision,
      test_evidence: accepted.test_evidence,
      test_caveat: accepted.test_caveat,
      boundary: accepted.boundary,
      invariant: accepted.invariant,
      limits: accepted.limits,
      verdict: "Accepted as a stable foundation seam at the recorded source revision."
    })
  end

  # JSON strings are valid YAML scalars and safely quote punctuation/newlines.
  defp yaml_string(value), do: Jason.encode!(to_string(value))
end

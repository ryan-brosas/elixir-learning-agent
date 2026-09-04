defmodule LearningAgent.Skills.Capsule do
  @moduledoc "Structured immutable foundation capsule for one stable seam."

  @required_fields [
    :seam,
    :question,
    :source,
    :path_symbol,
    :direct_source_excerpt,
    :source_digest,
    :source_revision,
    :boundary,
    :invariant,
    :limits,
    :verdict
  ]

  defstruct seam: nil,
            question: nil,
            source: nil,
            path_symbol: nil,
            direct_source_excerpt: nil,
            source_digest: nil,
            source_revision: nil,
            test_evidence: nil,
            test_caveat: nil,
            boundary: nil,
            invariant: nil,
            limits: nil,
            verdict: nil

  def required_fields, do: @required_fields

  def validate(%__MODULE__{} = capsule) do
    missing = Enum.reject(@required_fields, &present?(Map.get(capsule, &1)))

    cond do
      missing != [] ->
        {:error, missing}

      capsule.source_digest != digest(capsule.direct_source_excerpt) ->
        {:error, [:source_digest]}

      not present?(capsule.test_evidence) and not present?(capsule.test_caveat) ->
        {:error, [:test_evidence_or_caveat]}

      true ->
        :ok
    end
  end

  def new(attrs) when is_map(attrs), do: struct(%__MODULE__{}, attrs)

  defp digest(content),
    do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp present?(value),
    do: not is_nil(value) and (not is_binary(value) or String.trim(value) != "")
end

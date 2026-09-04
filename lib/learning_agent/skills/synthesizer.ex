defmodule LearningAgent.Skills.Synthesizer do
  @moduledoc "Deterministic renderer for direct-evidence foundation capsules."
  alias LearningAgent.Skills.Capsule

  def render_capsule(%Capsule{} = capsule) do
    case Capsule.validate(capsule) do
      :ok -> render_valid(capsule)
      {:error, reason} -> raise ArgumentError, "invalid foundation capsule: #{inspect(reason)}"
    end
  end

  def render_capsule!(capsule), do: render_capsule(capsule)

  defp render_valid(capsule) do
    test_binding =
      if present?(capsule.test_evidence) do
        "**Test evidence:** #{capsule.test_evidence}."
      else
        "**Test caveat:** #{capsule.test_caveat}."
      end

    """
    <!-- capsule-v2 -->
    <!-- producer: elixir-learning-agent -->
    # #{capsule.seam} — #{capsule.question}

    **Source:** #{capsule.source}.
    **Path/Symbol:** #{capsule.path_symbol}.
    **Source revision:** `#{capsule.source_revision}`.
    **Source digest:** `#{capsule.source_digest}`.

    ### Direct source excerpt
    ```text
    #{capsule.direct_source_excerpt}
    ```

    #{test_binding}

    **Question:** #{capsule.question}
    **Boundary:** #{capsule.boundary}
    **Invariant:** #{capsule.invariant}
    **Limits:** #{capsule.limits}

    ## Verdict
    #{capsule.verdict}
    """
  end

  def capsule_ref(seam), do: "references/" <> seam <> ".md"

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

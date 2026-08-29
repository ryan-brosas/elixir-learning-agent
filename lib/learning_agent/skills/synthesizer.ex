defmodule LearningAgent.Skills.Synthesizer do
  @moduledoc """
  Render capsule-v2 and foundation-leaf Markdown (docs/06 M7). Output follows the
  canonical templates (foundation-capsule.md / foundation-skill.md); synthesis is
  deterministic and validation is a separate step the model cannot bypass.
  """
  alias LearningAgent.Skills.Capsule

  @doc "Render one capsule-v2 document."
  def render_capsule(%Capsule{} = c) do
    """
    <!-- capsule-v2 -->
    # #{c.seam} — #{c.question}

    **Source:** #{c.source}. **Question:** #{c.question}

    **Path/Symbol:** #{c.path_symbol}.
    **Signature:** #{c.signature}.
    **Data Shape:** #{c.data_shape}.

    ### Decisive source
    ```text
    #{c.decisive_source}
    ```

    **Flow:** #{c.flow}.
    **Invariant:** #{c.invariant}.
    **Probe:** #{c.probe}.

    ## Verdict
    #{c.verdict}
    """
  end

  @doc "A capsule is stored at references/<seam>.md."
  def capsule_ref(seam), do: "references/" <> seam <> ".md"
end

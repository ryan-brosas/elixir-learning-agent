defmodule LearningAgent.Skills.Capsule do
  @moduledoc """
  Capsule-v2 model + validator (foundation-capsule.md template, docs/05 §17).

  Encodes the required fields of the canonical capsule template so synthesis and
  validation share one contract. A capsule is the unit of reusable behavior for
  one precise porting question.
  """

  @required_fields [
    :seam,
    :question,
    :source,
    :path_symbol,
    :signature,
    :data_shape,
    :decisive_source,
    :flow,
    :invariant,
    :probe,
    :verdict
  ]

  # Fields optional at construction (synthesis is incremental); validate/1 enforces.
  defstruct seam: nil,
            question: nil,
            source: nil,
            path_symbol: nil,
            signature: nil,
            data_shape: nil,
            decisive_source: nil,
            flow: nil,
            invariant: nil,
            probe: nil,
            retrieve: nil,
            verdict: nil

  @doc "Required capsule-v2 fields."
  def required_fields, do: @required_fields

  @doc "Validate: :ok | {:error, [missing]}"
  def validate(%__MODULE__{} = c) do
    missing = Enum.reject(@required_fields, fn f -> not is_nil(Map.get(c, f)) end)
    if missing == [], do: :ok, else: {:error, missing}
  end

  def new(attrs) when is_map(attrs), do: struct(%__MODULE__{}, attrs)
end

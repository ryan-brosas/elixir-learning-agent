defmodule LearningAgent.Notes.Validator do
  @moduledoc """
  Structural validation of a learning note (docs/06 Milestone 6, docs/05 §16).

  A note must contain the required canonical sections so downstream artifact
  synthesis and closure always have the context they need. Deterministic.
  """

  @required_sections [
    "architecture",
    "covered",
    "partial/uncited",
    "porter-questions",
    "selected-subsystem"
  ]

  def required_sections, do: @required_sections

  @doc "Validate a note body. Returns :ok | {:error, [missing_section]}."
  def validate(content) when is_binary(content) do
    missing =
      Enum.reject(@required_sections, fn section ->
        String.contains?(String.downcase(content), section)
      end)

    if missing == [], do: :ok, else: {:error, missing}
  end
end

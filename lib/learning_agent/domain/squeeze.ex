defmodule LearningAgent.Domain.Squeeze do
  @moduledoc """
  Finish metrics for a repository (docs/01 Closure).

  A repo is squeezed only after architecture is recorded and every discovered
  component and source seam has left partial/uncited into covered.
  """

  def architecture_recorded?(notes) when is_list(notes) do
    Enum.any?(notes, fn content ->
      body = section(content, "architecture")
      is_binary(body) and String.length(String.trim(body)) >= 20
    end)
  end

  def covered_keys(notes) when is_list(notes) do
    notes
    |> Enum.flat_map(&section_keys(&1, "covered"))
    |> MapSet.new()
  end

  def uncovered(inventory, notes) when is_list(inventory) and is_list(notes) do
    covered = covered_keys(notes)
    Enum.reject(inventory, &MapSet.member?(covered, &1))
  end

  def closed?(inventory, notes) when is_list(inventory) and is_list(notes) do
    cond do
      # Visited and nothing left on disk: drained, so a vanished source cannot
      # hot-loop the queue.
      inventory == [] and notes != [] -> true
      # Never visited (e.g. source not mounted yet): still owes its first pass.
      inventory == [] -> false
      architecture_recorded?(notes) -> uncovered(inventory, notes) == []
      true -> false
    end
  end

  def section_keys(content, name) do
    case section(content, name) do
      nil ->
        []

      body ->
        Regex.scan(~r/^- `([^`]+)`/m, body)
        |> Enum.map(fn [_, key] -> key end)
    end
  end

  @doc """
  Extract one markdown section body from a note. Public so the skill
  synthesizer can distill the learned sections into the operator-facing
  SKILL.md without re-parsing note markdown ad hoc.
  """
  def section(content, name) do
    pattern = ~r/^[ \t]*# #{Regex.escape(name)}\n(.*?)(?:\n[ \t]*# |\z)/ms

    case Regex.run(pattern, content || "") do
      [_, body] -> body
      _ -> nil
    end
  end
end

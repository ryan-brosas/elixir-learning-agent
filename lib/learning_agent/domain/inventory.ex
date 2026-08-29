defmodule LearningAgent.Domain.Inventory do
  @moduledoc """
  Subsystem & seam inventory and closure inputs
  (docs/01-domain-state-and-closure.md §7, §9, §10).

  Pure adjudication model over stable keys. No source tree crawling here; this is
  the deterministic seam bookkeeping the scheduler and validator draw from.
  """

  # kind values for subsystems vs seams
  @discovery [:unknown, :candidate, :confirmed]
  @adjudication [:unit, :covered, :partial, :omitted, :blocked]
  # states that block closure until terminal
  @unresolved [:unknown, :candidate, :partial]

  defmodule Item do
    @moduledoc """
    One inventory item: a subsystem and/or seam with its discovery + adjudication state.
    """
    @enforce_keys [:stable_key, :kind]
    defstruct stable_key: nil,
              kind: :seam,
              parent_id: nil,
              discovery_state: :unknown,
              adjudication_state: nil,
              reason_code: nil,
              source_path: nil,
              source_digest: nil
  end

  @doc "Create an inventory item with defaults."
  def new(attrs) when is_map(attrs) do
    %Item{
      stable_key: Map.fetch!(attrs, :stable_key),
      kind: Map.get(attrs, :kind, :seam),
      parent_id: Map.get(attrs, :parent_id),
      discovery_state: Map.get(attrs, :discovery_state, :unknown),
      adjudication_state: Map.get(attrs, :adjudication_state),
      reason_code: Map.get(attrs, :reason_code),
      source_path: Map.get(attrs, :source_path),
      source_digest: Map.get(attrs, :source_digest)
    }
  end

  @doc "All admissible discovery states."
  def discovery_states, do: @discovery

  @doc "All admissible adjudication states."
  def adjudication_states, do: @adjudication

  @doc "Adjudication states that prevent repository closure."
  def unresolved?(adjudication), do: adjudication in @unresolved

  @doc "Adjudication is terminal (covered, omitted, or blocked)."
  def terminal?(adjudication), do: adjudication in [:covered, :omitted, :blocked]

  @doc "Omitted/blocked items must carry a reason (design §7: reason_code required)."
  def requires_reason?(adjudication), do: adjudication in [:omitted, :blocked]
end

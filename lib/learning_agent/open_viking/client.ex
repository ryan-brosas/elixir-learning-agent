defmodule LearningAgent.OpenViking.Client do
  @moduledoc """
  OpenViking client behaviour (docs/03 §19, D-004). Maps to the MCP ops observed
  live in M0 (add_resource, find, read). Exact transport is a deployment decision;
  the outbox decouples local success from remote availability.
  """

  @callback add(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback find(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback read(String.t()) :: {:ok, map()} | {:error, term()}
end

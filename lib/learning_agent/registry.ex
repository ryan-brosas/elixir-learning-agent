defmodule LearningAgent.Registry do
  @moduledoc "Process registry for run workers keyed by run id."

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end

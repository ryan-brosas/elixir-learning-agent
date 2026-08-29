defmodule LearningAgent.Registry do
  @moduledoc """
  Process registry used to resolve run workers by id for cancellation.
  """
  use GenServer

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state}
end

defmodule LearningAgent.RunSupervisor do
  @moduledoc """
  DynamicSupervisor for pass workers (design §8). Children are temporary because
  durable state drives restart; recovery decides whether to resume or requeue.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start a worker for a claimed run; returns {:ok, pid} | {:error, reason}."
  def start_worker(run) do
    DynamicSupervisor.start_child(__MODULE__, {LearningAgent.RunWorker, run})
  end
end

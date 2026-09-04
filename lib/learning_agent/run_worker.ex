defmodule LearningAgent.RunWorker do
  @moduledoc """
  One repository pass worker. Temporary child of RunSupervisor; SQL remains the
  source of truth. Each claimed run records a pin-scoped observation, accepts any
  directly evidenced seam capsule, activates the complete foundation projection,
  then releases the lease. It has no procedure-promotion capability.
  """
  use GenServer
  require Logger
  alias LearningAgent.LearningPass

  def child_spec({run, model}) do
    %{
      id: {__MODULE__, run.id},
      start: {__MODULE__, :start_link, [{run, model}]},
      restart: :temporary
    }
  end

  def child_spec(run), do: child_spec({run, nil})

  def start_link({%LearningAgent.Run{} = run, model}) do
    GenServer.start_link(__MODULE__, {run, model},
      name: {:via, Registry, {LearningAgent.Registry, run.id}}
    )
  end

  def start_link(%LearningAgent.Run{} = run), do: start_link({run, nil})

  @impl true
  def init({run, model}) do
    {:ok, {run, model}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, {run, model}) do
    result =
      try do
        LearningPass.execute(run, model)
      rescue
        error ->
          reason = {:exception, Exception.message(error)}
          LearningPass.abort(run, reason)
          {:error, reason}
      end

    case result do
      {:ok, _} ->
        {:stop, :normal, {run, model}}

      {:error, reason} ->
        Logger.error("run_worker_aborted run=#{run.id} reason=#{inspect(reason)}")
        {:stop, :normal, {run, model}}
    end
  end
end

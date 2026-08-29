defmodule LearningAgent.Application do
  @moduledoc """
  Application supervision (DESIGN.md §9). Starts the repo then scheduler-side
  processes. Recovery runs once after the supervisor tree is up so it can query
  the repo. In :test the scheduler and lease renewer are disabled (started
  explicitly by tests that exercise them) so background loops never fight the
  Ecto Sandbox.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = supervisor_children()

    case Supervisor.start_link(children, strategy: :one_for_one, name: LearningAgent.Supervisor) do
      {:ok, sup} ->
        LearningAgent.Recovery.run()
        {:ok, sup}

      error ->
        error
    end
  end

  defp supervisor_children do
    base = [LearningAgent.Repo, LearningAgent.Registry, LearningAgent.RunSupervisor]
    base = if server_enabled?(), do: base ++ [web_spec()], else: base

    ~w(lease_renewer scheduler)a
    |> Enum.reduce(base, fn key, acc ->
      if Application.get_env(:learning_agent, key) == :disabled,
        do: acc,
        else: acc ++ [module_for(key)]
    end)
  end

  # Serve the operator + health HTTP API. Enabled only when :http_port is set (so
  # tests under :test, which set no port, don't open a listener).
  defp server_enabled?, do: Application.get_env(:learning_agent, :http_port) != nil

  defp web_spec do
    port = Application.get_env(:learning_agent, :http_port, 4000)
    {Plug.Cowboy, scheme: :http, plug: {LearningAgentWeb.Router, []}, options: [port: port]}
  end

  defp module_for(:lease_renewer), do: LearningAgent.LeaseRenewer
  defp module_for(:scheduler), do: LearningAgent.Scheduler
end

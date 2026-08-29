defmodule LearningAgent.LeaseRenewer do
  @moduledoc """
  Independent lease renewal heartbeat (docs/01 §15). Renews every live, unexpired,
  unreleased lease held by any holder on this node. Renewal is decoupled from
  model/provider calls so a slow model turn never loses the lease.
  """
  use GenServer
  import Ecto.Query
  alias LearningAgent.{Repo, Lease}
  alias LearningAgent.LeaseContext

  @interval :timer.seconds(3)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :renew, @interval)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:renew, state) do
    Process.send_after(self(), :renew, @interval)
    renew_pending()
    {:noreply, state}
  end

  @doc "Renew every lease that is still live (not released, not expired)."
  def renew_pending do
    now = DateTime.utc_now()

    query =
      from(l in Lease,
        where: is_nil(l.released_at) and l.expires_at > ^now,
        select: l
      )

    Repo.all(query)
    |> Enum.each(fn lease ->
      case LeaseContext.renew(lease, lease.epoch, lease.holder_id) do
        {:ok, _} -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end
end

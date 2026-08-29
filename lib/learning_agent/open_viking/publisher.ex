defmodule LearningAgent.OpenViking.Publisher do
  @moduledoc """
  Drives the OpenViking outbox (docs/03 §16-§18). Claims pending events, dispatches
  to the configured client (add/find/read), marks delivered on success, retries on
  transient failure, records permanent failure. Never deletes OpenViking resources.
  """
  alias LearningAgent.{OutboxContext, OutboxEvent}

  @doc "Process one claim batch. Returns {:ok, results}."
  def drain(client, limit \\ 10) do
    results = OutboxContext.claim_pending(limit) |> Enum.map(&dispatch(client, &1))
    {:ok, results}
  end

  defp dispatch(client, %OutboxEvent{event_type: type, payload: payload} = event) do
    case deliver(client, type, payload || %{}) do
      {:ok, remote_ref} -> OutboxContext.deliver(event, remote_ref)
      {:error, {:permanent, reason}} -> OutboxContext.fail(event, reason)
      {:error, reason} -> OutboxContext.retry(event, reason)
    end
  end

  defp deliver(client, "add_learning_note", payload),
    do: client.add.(Map.get(payload, "destination", ""), kw(payload))

  defp deliver(client, "add_capsule", payload),
    do: client.add.(Map.get(payload, "destination", ""), kw(payload))

  defp deliver(client, "verify_symbol", payload) do
    case client.find.(Map.get(payload, "query", ""), []) do
      {:ok, [_hit | _]} -> {:ok, :verified}
      {:ok, []} -> {:error, {:transient, :not_found}}
      other -> other
    end
  end

  defp deliver(_client, type, _payload), do: {:error, {:permanent, {:unsupported_event, type}}}

  defp kw(payload), do: Enum.map(payload, fn {k, v} -> {String.to_atom(k), v} end)
end

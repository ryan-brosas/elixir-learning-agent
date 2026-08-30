defmodule LearningAgent.OpenViking.Relayer do
  @moduledoc """
  Periodic OpenViking outbox drain. Missing MCP is skip, never crash.
  """
  use GenServer
  require Logger
  alias LearningAgent.OpenViking.{HttpMcp, Publisher}
  alias LearningAgent.OutboxContext

  @tick :timer.seconds(5)
  @batch 100
  @max_batches 20
  @stale_ttl :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    _ = OutboxContext.reclaim_stale(stale_cutoff())

    case client() do
      {:ok, map, after_fn} ->
        try do
          drain_loop(@max_batches, map)
        after
          after_fn.()
        end

      :skip ->
        :ok
    end

    schedule()
    {:noreply, state}
  end

  def drain_once(limit \\ @batch) do
    case client() do
      {:ok, map, after_fn} ->
        try do
          Publisher.drain(map, limit)
        after
          after_fn.()
        end

      :skip ->
        :ok
    end
  end

  # Drain batches back to back within one tick so a large backlog clears in
  # minutes, not hours; the batch cap bounds each tick's work.
  defp drain_loop(remaining, client)

  defp drain_loop(0, _client), do: :ok

  defp drain_loop(remaining, client) do
    case Publisher.drain(client, @batch) do
      {:ok, results} when length(results) < @batch -> :ok
      {:ok, _results} -> drain_loop(remaining - 1, client)
    end
  end

  defp stale_cutoff, do: DateTime.add(DateTime.utc_now(), -@stale_ttl, :millisecond)

  defp client do
    case Application.get_env(:learning_agent, :open_viking_client) do
      %{add: add, find: find} = map when is_function(add, 2) and is_function(find, 2) ->
        {:ok, Map.put_new(map, :read, fn _ -> {:error, :not_configured} end), fn -> :ok end}

      _ ->
        ov_http()
    end
  end

  # OpenViking serves MCP over Streamable HTTP (POST /mcp), not the framed TCP
  # transport; a missing endpoint stays a skip, never a crash.
  defp ov_http do
    host = Application.get_env(:learning_agent, :ov_host) || System.get_env("LA_OV_HOST")

    port =
      Application.get_env(:learning_agent, :ov_port) || parse_port(System.get_env("LA_OV_PORT"))

    if is_binary(host) and host != "" and is_integer(port) do
      case HttpMcp.start(host, port) do
        {:ok, session} ->
          {:ok, http_client(session), fn -> :ok end}

        {:error, reason} ->
          Logger.debug("openviking_mcp_skip reason=#{inspect(reason)}")
          :skip
      end
    else
      :skip
    end
  end

  defp http_client(session) do
    %{
      add: fn dest, kw ->
        HttpMcp.call(session, "add_resource", Map.new([{:destination, dest} | List.wrap(kw)]))
      end,
      find: fn query, _ -> HttpMcp.call(session, "find", %{query: query}) end,
      read: fn uri -> HttpMcp.call(session, "read", %{uri: uri}) end
    }
  end

  defp parse_port(value) when is_binary(value) do
    case Integer.parse(value) do
      {port, ""} -> port
      _ -> nil
    end
  end

  defp parse_port(_), do: nil

  defp schedule, do: Process.send_after(self(), :tick, @tick)
end

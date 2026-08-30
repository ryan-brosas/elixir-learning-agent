defmodule LearningAgent.MCP.Client do
  @moduledoc """
  MCP client: one socket + request correlation (docs/06 M4, docs/05 §13).

  Requests carry incremental ids; each pending call has a timer. Responses are
  correlated by id: a response for an unknown id is discarded (late response).
  Timeout, disconnect, and explicit cancel fail the pending caller; the server
  is a normal GenServer so it can own the active socket.
  """

  use GenServer
  alias LearningAgent.MCP.{Protocol, Transport}

  def start_link(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    start_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, nil} -> []
        {:ok, name} -> [name: name]
        :error -> [name: __MODULE__]
      end

    GenServer.start_link(
      __MODULE__,
      %{host: host, port: port, socket: nil, next_id: 1, pending: %{}},
      start_opts
    )
  end

  @doc "Send a request and await the result. Returns {:ok, result} | {:error, reason}."
  def call(server, method, params \\ %{}, timeout \\ 5_000) do
    GenServer.call(server, {:call, method, params, timeout}, :infinity)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case Transport.connect(state.host, state.port, active: true) do
      {:ok, socket} -> {:noreply, %{state | socket: socket}}
      {:error, reason} -> {:stop, {:connect_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:call, method, params, timeout}, from, state) do
    if is_nil(state.socket) do
      GenServer.reply(from, {:error, :disconnected})
      {:noreply, state}
    else
      id = state.next_id

      case Transport.send(state.socket, Protocol.encode_request(id, method, params)) do
        :ok ->
          timer = Process.send_after(self(), {:mcp_timeout, id}, timeout)
          p = Map.put(state.pending, id, %{from: from, timer: timer})
          {:noreply, %{state | next_id: id + 1, pending: p}}

        {:error, r} ->
          GenServer.reply(from, {:error, {:send_failed, r}})
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    Transport.active_continue(socket)
    {:noreply, absorb(data, state)}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    fail_all(state.pending, {:error, :disconnected})
    {:stop, :disconnected, %{state | pending: %{}}}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    fail_all(state.pending, {:error, {:tcp_error, reason}})
    {:stop, {:tcp_error, reason}, %{state | pending: %{}}}
  end

  def handle_info({:mcp_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {p, pending} ->
        Process.cancel_timer(p.timer)
        GenServer.reply(p.from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  defp absorb(data, state) do
    case Protocol.split_frames(data) do
      {:ok, frames, _rest} -> Enum.reduce(frames, state, &on_frame/2)
      {:error, :frame_too_large} -> state
    end
  end

  defp on_frame(line, state) do
    case Protocol.decode_line(line) do
      {:response, %{"id" => id, "result" => r}} ->
        resolve(state, id, {:ok, r})

      {:response, %{"id" => id, "error" => e}} ->
        resolve(state, id, {:error, {:jsonrpc_error, e}})

      _ ->
        state
    end
  end

  defp resolve(state, id, result) do
    case Map.pop(state.pending, id) do
      # late response for an unknown id: drop
      {nil, _} ->
        state

      {p, pending} ->
        Process.cancel_timer(p.timer)
        GenServer.reply(p.from, result)
        %{state | pending: pending}
    end
  end

  defp fail_all(pending, result) do
    Enum.each(pending, fn {_id, p} ->
      Process.cancel_timer(p.timer)
      GenServer.reply(p.from, result)
    end)
  end
end

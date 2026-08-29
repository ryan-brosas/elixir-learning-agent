defmodule LearningAgent.MCP.Transport do
  @moduledoc """
  Newline-delimited JSON transport over a TCP socket.

  Supports both passive (sync recv) and active (:once) modes. The client uses
  active mode so each frame arrives as {:tcp, socket, data} and the GenServer can
  correlate responses; long-running servers / tests use passive recv_line.
  """

  alias LearningAgent.MCP.Protocol

  @doc "Open a connection. opts[:active] (default false) enables active :once."
  def connect(host, port, opts \\ []) do
    base = [:binary, packet: :raw, active: false, nodelay: true]
    tcp_opts = if Keyword.get(opts, :active), do: base ++ [active: :once], else: base
    :gen_tcp.connect(String.to_charlist(host), port, tcp_opts, :infinity)
  end

  @doc "Re-arm active-once so the owner keeps receiving {:tcp, data}."
  def active_continue(socket), do: :inet.setopts(socket, active: :once)

  def send(socket, frame), do: :gen_tcp.send(socket, frame)

  @doc "Passive read of one complete line. Used by servers/stub tests."
  def recv_line(socket, timeout \\ 5_000) do
    recv_line(socket, timeout, "")
  end

  defp recv_line(socket, timeout, acc) do
    if byte_size(acc) > Protocol.max_frame_size() do
      {:error, :frame_too_large}
    else
      case :gen_tcp.recv(socket, 0, timeout) do
        {:ok, data} ->
          full = acc <> data

          case :binary.split(full, "\n") do
            [line, _] -> {:ok, line}
            [_] -> recv_line(socket, timeout, full)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def close(socket), do: :gen_tcp.close(socket)
end

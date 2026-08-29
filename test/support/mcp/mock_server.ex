defmodule LearningAgent.MCP.MockServer do
  @moduledoc """
  A scripted, blocking TCP MCP stub for tests (docs/05 §31).

  Listens on 127.0.0.1:0, accepts one connection, reads JSON-RPC frames, and
  answers from a script of {method, result}. Records call order for asserting the
  discovery sequence. Exercises the real socket transport.
  """
  alias LearningAgent.MCP.{Protocol, Transport}

  def start(script) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_addr, port}} = :inet.sockname(listener)
    pid = spawn(fn -> accept_loop(listener, script, []) end)
    %{port: port, pid: pid}
  end

  defp accept_loop(listener, script, calls) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} -> handle(socket, script, calls)
      {:error, :closed} -> :ok
    end
  end

  defp handle(socket, script, calls) do
    case Transport.recv_line(socket) do
      {:ok, line} ->
        case Protocol.decode_line(line) do
          {:request, %{"id" => id, "method" => method}} ->
            result = respond(script, method)
            Transport.send(socket, Protocol.encode_response(id, result))
            handle(socket, script, calls ++ [method])

          _ ->
            handle(socket, script, calls)
        end

      {:error, _} ->
        :ok
    end
  end

  defp respond(script, method) do
    case List.keyfind(script, method, 0) do
      {_, result} -> result
      nil -> %{"error" => "no scripted response for " <> method}
    end
  end

  def close(listener), do: :gen_tcp.close(listener)
end

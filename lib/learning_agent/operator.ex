defmodule LearningAgent.Operator do
  @moduledoc """
  Operator auth + roles (docs/04 §4). Bearer-token auth with viewer/operator/administrator
  roles. The model has no operator role; the API never exposes arbitrary tool execution.
  """

  @roles [:viewer, :operator, :administrator]
  @tokens %{
    "view-token" => {:viewer, "ops"},
    "op-token" => {:operator, "ops"},
    "admin-token" => {:administrator, "ops"}
  }

  def roles, do: @roles

  @doc "Resolve a bearer token to {role, subject} | :invalid."
  def authenticate(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Map.get(@tokens, token, :invalid)
      _ -> :invalid
    end
  end

  @doc "True when actual role meets the required role."
  def authorize?(required, actual) do
    rank = fn
      :viewer -> 1
      :operator -> 2
      :administrator -> 3
    end

    rank.(actual) >= rank.(required)
  end
end

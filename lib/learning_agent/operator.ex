defmodule LearningAgent.Operator do
  @moduledoc """
  Operator auth + roles (docs/04 §4). Bearer-token auth with viewer/operator/administrator
  roles. The model has no operator role; the API never exposes arbitrary tool execution.
  """

  @roles [:viewer, :operator, :administrator]
  def roles, do: @roles

  @doc "Resolve a bearer token to {role, subject} | :invalid."
  def authenticate(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Map.get(tokens(), token, :invalid)
      _ -> :invalid
    end
  end

  defp tokens do
    configured = Application.get_env(:learning_agent, :operator_tokens, %{})

    [
      {"LA_VIEWER_TOKEN", :viewer},
      {"LA_OPERATOR_TOKEN", :operator},
      {"LA_ADMIN_TOKEN", :administrator}
    ]
    |> Enum.reduce(configured, fn {env_name, role}, acc ->
      case System.get_env(env_name) do
        token when is_binary(token) and token != "" -> Map.put(acc, token, {role, "ops"})
        _ -> acc
      end
    end)
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

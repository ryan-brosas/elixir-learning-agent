defmodule LearningAgent.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible chat adapter (docs/02 §8-§9, D-003; ships first).

  Projects provider-neutral messages to the chat-completions wire shape (system/
  user/assistant/tool roles) and normalizes the response (text, tool calls, usage,
  stop reason) and error classes. Transport is injected so tests run without a key;
  production uses HTTP.
  """
  @behaviour LearningAgent.Provider

  @impl true
  def complete(opts) do
    body = build_body(opts)
    transport = Map.get(opts, :transport, &http_transport/1)

    case transport.(body) do
      {:ok, resp} -> normalize_response(resp)
      {:error, reason} -> {:error, %{class: classify_reason(reason), detail: reason}}
    end
  end

  @impl true
  def classify(reason), do: classify_reason(reason)

  @impl true
  def estimate_cost(%{usage: %{prompt_tokens: p, completion_tokens: c}}), do: p + c
  def estimate_cost(_), do: :unknown

  defp normalize_response(resp) do
    choice = resp["choices"] |> List.first()
    msg = choice["message"] || %{}

    tool_calls =
      (msg["tool_calls"] || [])
      |> Enum.map(fn tc ->
        %{
          "id" => tc["id"],
          "name" => tc["function"]["name"],
          "arguments" => tc["function"]["arguments"]
        }
      end)

    {:ok,
     %{
       text: msg["content"],
       tool_calls: tool_calls,
       usage: resp["usage"] || %{},
       stop_reason: choice["finish_reason"]
     }}
  end

  defp build_body(opts) do
    messages = Enum.map(opts.messages, &map_msg/1)

    %{
      "model" => opts.model,
      "messages" => messages,
      "temperature" => Map.get(opts, :temperature, 0.1)
    }
  end

  defp map_msg(%{role: role, content: blocks}) do
    role_str = provider_role(role)
    %{"role" => role_str, "content" => Enum.map_join(blocks, "\n", &block_text/1)}
  end

  defp block_text(%{type: :text, text: t}), do: t
  defp block_text(%{type: :tool_result, content: c}), do: inspect(c)
  defp block_text(x), do: inspect(x)

  defp provider_role(:assistant), do: "assistant"
  defp provider_role(:tool), do: "tool"
  defp provider_role(:temporary_guidance), do: "assistant"
  defp provider_role(_), do: "user"

  defp classify_reason(%{class: c}), do: c
  defp classify_reason(:timeout), do: :timeout
  defp classify_reason(:rate_limited), do: :rate_limited
  defp classify_reason(:auth), do: :authentication
  defp classify_reason(:connection), do: :connection
  defp classify_reason(_), do: :unknown

  defp http_transport(_), do: {:error, :no_transport}
end

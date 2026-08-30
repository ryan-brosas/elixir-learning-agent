defmodule LearningAgent.Providers.OpenAICompatibleTest do
  use ExUnit.Case, async: true

  alias LearningAgent.Providers.OpenAICompatible

  test "projects messages and normalizes completion usage and stop reason" do
    test_pid = self()

    transport = fn body ->
      send(test_pid, {:request, body})

      {:ok,
       %{
         "choices" => [
           %{"message" => %{"content" => "done", "tool_calls" => []}, "finish_reason" => "stop"}
         ],
         "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 1}
       }}
    end

    assert {:ok, response} =
             OpenAICompatible.complete(%{
               model: "fixture-model",
               messages: [%{role: :operator, content: [%{type: :text, text: "hello"}]}],
               transport: transport
             })

    assert response.text == "done"
    assert response.tool_calls == []
    assert response.usage == %{"prompt_tokens" => 3, "completion_tokens" => 1}
    assert response.stop_reason == "stop"

    assert_receive {:request,
                    %{
                      "model" => "fixture-model",
                      "messages" => [%{"role" => "user", "content" => "hello"}]
                    }}
  end

  test "normalizes OpenAI and Ollama model list shapes" do
    assert {:ok, ["gpt-4o-mini"]} =
             OpenAICompatible.list_models(%{
               list_transport: fn -> {:ok, %{"data" => [%{"id" => "gpt-4o-mini"}]}} end
             })

    assert {:ok, ["llama3"]} =
             OpenAICompatible.list_models(%{
               list_transport: fn -> {:ok, %{"models" => [%{"name" => "llama3"}]}} end
             })
  end

  test "classifies malformed provider responses instead of crashing" do
    assert {:error, %{class: :malformed_response}} =
             OpenAICompatible.complete(%{
               model: "fixture-model",
               messages: [],
               transport: fn _body -> {:ok, %{"choices" => []}} end
             })
  end
end

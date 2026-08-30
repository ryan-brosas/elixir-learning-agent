defmodule LearningAgent.AgentLoopTest do
  use ExUnit.Case, async: true
  alias LearningAgent.AgentLoop
  alias LearningAgent.Domain.Budget

  defp scripted_provider(script) do
    {:ok, pid} = Agent.start_link(fn -> script end)

    provider = fn _model, _messages ->
      Agent.get_and_update(pid, fn
        [head | rest] -> {head, rest}
        [] -> {{:ok, %{tool_calls: [], text: "done"}}, []}
      end)
    end

    {pid, provider}
  end

  defp opts(provider, overrides \\ []) do
    base = %{
      provider: provider,
      model: "test-model",
      messages: [],
      budget: Budget.new(%{model_calls: 10}),
      context: %{gate: :preflight, root: "/tmp/x", run_id: "r"},
      tool_fn: fn _name, _args, _plan -> {:ok, :ok} end
    }

    Map.merge(base, Map.new(overrides))
  end

  test "loop runs a tool call then finishes" do
    script = [
      {:ok, %{tool_calls: [%{name: "run.record_blocker", arguments: "{}"}]}},
      {:ok, %{tool_calls: [], text: "done"}}
    ]

    {_pid, provider} = scripted_provider(script)
    assert {:ok, %{stop: :finished, text: "done"}} = AgentLoop.run(opts(provider))
  end

  test "budget exhaustion stops before a provider call" do
    {_pid, provider} = scripted_provider([])
    killed = Budget.new(%{model_calls: 0})
    assert {:error, :budget_exhausted} = AgentLoop.run(opts(provider, budget: killed))
  end

  test "an unapproved tool target is denied and stops" do
    script = [{:ok, %{tool_calls: [%{name: "nuke", arguments: "{}"}]}}]
    {_pid, provider} = scripted_provider(script)
    assert {:error, {:denied, _reason}} = AgentLoop.run(opts(provider))
  end

  test "max turns stops a loop that never finishes" do
    never =
      List.duplicate({:ok, %{tool_calls: [%{name: "run.record_blocker", arguments: "{}"}]}}, 100)

    {_pid, provider} = scripted_provider(never)
    assert {:error, :max_turns} = AgentLoop.run(opts(provider, max_turns: 4))
  end

  test "transient model failures retry until a later attempt succeeds" do
    {_pid, provider} =
      scripted_provider([
        {:error, %{class: :timeout, detail: :t1}},
        {:error, %{class: :rate_limited, detail: :t2}},
        {:ok, %{tool_calls: [], text: "recovered"}}
      ])

    assert {:ok, %{stop: :finished, text: "recovered"}} =
             AgentLoop.run(opts(provider, model_retries: 100, retry_sleep: fn _ -> :ok end))
  end

  test "transient model failures exhaust the retry limit" do
    {_pid, provider} =
      scripted_provider(List.duplicate({:error, %{class: :timeout, detail: :t}}, 100))

    assert {:error, :provider_timeout} =
             AgentLoop.run(opts(provider, model_retries: 100, retry_sleep: fn _ -> :ok end))
  end

  test "authentication failures do not retry" do
    {_pid, provider} =
      scripted_provider([
        {:error, %{class: :authentication, detail: :auth}},
        {:ok, %{tool_calls: [], text: "should-not-run"}}
      ])

    assert {:error, {:provider, :authentication}} =
             AgentLoop.run(opts(provider, model_retries: 100, retry_sleep: fn _ -> :ok end))
  end
end

defmodule LearningAgent.ModelRetryRateLimitTest do
  use ExUnit.Case, async: true
  alias LearningAgent.ModelRetry

  test "rate-limited calls keep retrying through the quota window instead of giving up" do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      n = Agent.get_and_update(pid, &{&1 + 1, &1 + 1})

      if n < 6 do
        {:error, %{class: :rate_limited, detail: n}}
      else
        {:ok, :quota_window_passed}
      end
    end

    assert {:ok, :quota_window_passed} =
             ModelRetry.call(fun, max_attempts: 30, sleep: fn _ -> :ok end)

    assert Agent.get(pid, & &1) == 6
  end

  test "rate-limited calls exhaust the cap without success when the quota never opens" do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(pid, &(&1 + 1))
      {:error, %{class: :rate_limited}}
    end

    assert {:error, %{class: :rate_limited}} =
             ModelRetry.call(fun, max_attempts: 3, sleep: fn _ -> :ok end)

    assert Agent.get(pid, & &1) == 3
  end
end

defmodule LearningAgent.ModelRetryTest do
  use ExUnit.Case, async: true
  alias LearningAgent.ModelRetry

  test "parse_limit accepts 1 through 100" do
    assert ModelRetry.parse_limit(1) == {:ok, 1}
    assert ModelRetry.parse_limit("100") == {:ok, 100}
    assert ModelRetry.parse_limit(0) == {:error, :model_retry_limit_invalid}
    assert ModelRetry.parse_limit(101) == {:error, :model_retry_limit_invalid}
  end

  test "retries transient errors and stops on success" do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      n = Agent.get_and_update(pid, &{&1 + 1, &1 + 1})

      if n < 4 do
        {:error, %{class: :connection, detail: n}}
      else
        {:ok, :hit}
      end
    end

    assert {:ok, :hit} = ModelRetry.call(fun, max_attempts: 100, sleep: fn _ -> :ok end)
    assert Agent.get(pid, & &1) == 4
  end

  test "does not retry authentication errors" do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(pid, &(&1 + 1))
      {:error, %{class: :authentication, detail: :nope}}
    end

    assert {:error, %{class: :authentication}} =
             ModelRetry.call(fun, max_attempts: 100, sleep: fn _ -> :ok end)

    assert Agent.get(pid, & &1) == 1
  end

  test "gives up after the attempt cap" do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(pid, &(&1 + 1))
      {:error, %{class: :timeout}}
    end

    assert {:error, %{class: :timeout}} =
             ModelRetry.call(fun, max_attempts: 100, sleep: fn _ -> :ok end)

    assert Agent.get(pid, & &1) == 100
  end
end

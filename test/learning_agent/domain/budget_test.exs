defmodule LearningAgent.Domain.BudgetTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.Budget

  test "consuming within a limit succeeds and tracks usage" do
    b = Budget.new(%{model_calls: 4})
    assert {:ok, b1} = Budget.consume(b, :model_calls)
    assert {:ok, b2} = Budget.consume(b1, :model_calls)
    assert {:ok, b3} = Budget.consume(b2, :model_calls)
    assert Budget.remaining(b3, :model_calls) == 3
    # under limit of 4
    refute Budget.exhausted?(b3)
  end

  test "exceeding a limit is rejected and does not mutate" do
    b = Budget.new(%{model_calls: 2})
    assert {:ok, b1} = Budget.consume(b, :model_calls, 2)
    assert {:error, :limit_exceeded} = Budget.consume(b1, :model_calls)
    assert Budget.remaining(b1, :model_calls) == 2
  end

  test "no limit means unlimited until other limits are set" do
    b = Budget.new()
    assert {:ok, b1} = Budget.consume(b, :source_bytes, 1_000_000)
    assert Budget.remaining(b1, :source_bytes) == 1_000_000
  end

  test "unknown counter is rejected" do
    b = Budget.new()
    assert {:error, :unknown_counter} = Budget.consume(b, :not_a_counter)
  end

  test "exhausted? is true when a configured limit is reached" do
    b = Budget.new(%{model_calls: 1})
    assert {:ok, b1} = Budget.consume(b, :model_calls)
    assert Budget.exhausted?(b1)
  end

  test "exhaustion is a blocker, never completion" do
    b = Budget.new(%{estimated_cost_cents: 0})
    assert Budget.exhausted?(b)
  end

  test "merge_report consumes input+output tokens" do
    b = Budget.new(%{input_tokens: 100, output_tokens: 100})
    {:ok, b1} = Budget.merge_report(b, %{input_tokens: 40, output_tokens: 20})
    assert Budget.remaining(b1, :input_tokens) == 40
    assert Budget.remaining(b1, :output_tokens) == 20
  end
end

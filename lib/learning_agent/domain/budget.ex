defmodule LearningAgent.Domain.Budget do
  @moduledoc """
  Bounded per-run resource accounting (docs/01 §14, docs/02 §20).

  Pure arithmetic over typed counters. Budget exhaustion yields a blocker, never
  completion. The model cannot raise a budget; only operators may increase a
  queued or paused run's budget.
  """

  @enforce_keys []
  defstruct limits: %{}, used: %{}

  @counters [
    :model_calls,
    :input_tokens,
    :output_tokens,
    :estimated_cost_cents,
    :mcp_calls,
    :source_bytes,
    :source_reads,
    :probe_executions,
    :artifact_bytes_staged,
    :wall_clock_ms,
    :policy_denials
  ]

  @doc "Recognized budget counters."
  def counters, do: @counters

  @doc "New budget with configured limits (empty map = unlimited counters)."
  def new(limits \\ %{}) when is_map(limits) do
    %__MODULE__{
      limits: Map.merge(default_limits(), limits),
      used: Map.new(@counters, &{&1, 0})
    }
  end

  @doc "Default limits (operator overridable). Zero/absent = unlimited."
  def default_limits, do: %{}

  @doc "Is this counter within its configured limit after consuming `amount`?"
  def within_limit?(budget, counter, amount) do
    limit = Map.get(budget.limits, counter)
    limit == nil or Map.get(budget.used, counter, 0) + abs(amount) <= limit
  end

  @doc "Atomically consume one counter. Returns {:ok, new_budget} or {:error, :limit_exceeded}."
  def consume(budget, counter, amount \\ 1) do
    if counter in @counters,
      do: do_consume(budget, counter, amount),
      else: {:error, :unknown_counter}
  end

  defp do_consume(%__MODULE__{} = b, counter, amount) when is_integer(amount) and amount >= 0 do
    if consume_limit?(b, counter, amount) do
      {:ok, %{b | used: Map.update!(b.used, counter, &(&1 + amount))}}
    else
      {:error, :limit_exceeded}
    end
  end

  defp consume_limit?(b, counter, amount) do
    case Map.get(b.limits, counter) do
      nil -> true
      limit -> Map.get(b.used, counter, 0) + amount <= limit
    end
  end

  @doc """
  Combine provider-reported usage when a provider reports it (docs-02 §20).
  Returns {:ok, new_budget} or {:error, reason} without mutating on error.
  """
  def merge_report(budget, %{input_tokens: i, output_tokens: o}) do
    with {:ok, b1} <- consume(budget, :input_tokens, i),
         {:ok, b2} <- consume(b1, :output_tokens, o) do
      {:ok, b2}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def merge_report(budget, _), do: {:ok, budget}

  def remaining(budget, counter), do: Map.get(budget.used, counter, 0)

  def exhausted?(budget) do
    Enum.any?(budget.limits, fn
      {c, lim} -> Map.get(budget.used, c, 0) >= lim
    end)
  end
end

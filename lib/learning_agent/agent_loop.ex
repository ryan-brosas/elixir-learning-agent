defmodule LearningAgent.AgentLoop do
  @moduledoc """
  Bounded agent loop (docs/02 §2-§3, docs/05 §11).

  The model proposes one bounded action at a time; the loop validates it via the
  tool firewall, persists the observation before the next turn, enforces budgets,
  and stops on completion/blocker/failure/cancel/budget. It never calls an
  unapproved tool and never exceeds the turn cap.
  """
  alias LearningAgent.ToolPolicy
  alias LearningAgent.Domain.Budget

  @default_max_turns 20

  @doc "Run a turn loop. opts: %{provider, model, messages, tool_fn, context, budget, cancel?}"
  def run(opts) do
    do_run(opts, Map.get(opts, :messages, []), opts.budget, 0)
  end

  defp do_run(opts, messages, budget, turns) do
    cond do
      Map.get(opts, :cancel?, false) -> {:error, :cancelled}
      Budget.exhausted?(budget) -> {:error, :budget_exhausted}
      turns >= Map.get(opts, :max_turns, @default_max_turns) -> {:error, :max_turns}
      true -> turn(opts, messages, budget, turns)
    end
  end

  defp turn(opts, messages, budget, turns) do
    {:ok, budget} = Budget.consume(budget, :model_calls, 1)

    case opts.provider.(opts.model, messages) do
      {:ok, %{tool_calls: []} = resp} ->
        {:ok, %{stop: :finished, text: resp.text}}

      {:ok, %{tool_calls: [call]}} ->
        case execute_one(opts, call, messages) do
          {:ok, new_messages} -> do_run(opts, new_messages, budget, turns + 1)
          {:error, _} = err -> err
        end

      {:ok, %{tool_calls: _}} ->
        {:error, :parallel_calls_rejected}

      {:error, %{class: :timeout}} ->
        if turns < 1,
          do: do_run(opts, messages, budget, turns + 1),
          else: {:error, :provider_timeout}

      {:error, %{class: class}} ->
        {:error, {:provider, class}}
    end
  end

  defp execute_one(opts, call, messages) do
    name = Map.get(call, :name) || Map.get(call, "name")
    args = decode_args(Map.get(call, :arguments) || Map.get(call, "arguments"))
    ctx = Map.get(opts, :context, %{})

    case ToolPolicy.evaluate(name, args, ctx) do
      {:allow, plan} ->
        case opts.tool_fn.(name, args, plan) do
          {:ok, result} -> {:ok, messages ++ [tool_result_block(result)]}
          {:error, reason} -> {:error, {:handler, reason}}
        end

      {:deny, reason} ->
        {:error, {:denied, reason}}
    end
  end

  defp tool_result_block(result), do: %{type: :tool_result, content: result}
  defp decode_args(s) when is_binary(s), do: Jason.decode!(s, keys: :atoms)
  defp decode_args(m) when is_map(m), do: m
  defp decode_args(_), do: %{}
end

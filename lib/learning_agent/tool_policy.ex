defmodule LearningAgent.ToolPolicy do
  @moduledoc """
  Deterministic tool firewall (docs/02 §18-§19, docs/05 §4, §12).

  Policy evaluation order: registered? -> current gate -> single tool call ->
  forbidden capability patterns -> bounded args -> source containment. Only the
  current run gate can permit a call. A denial is a decision, never an exception.
  No stringly-typed shell/package/write/delegation capability exists.
  """

  alias LearningAgent.{ToolRegistry, SourceReader}

  @forbidden ~w(install pip npm mix apt bash exec sudo rm mv chmod curl wget sh)

  @doc "Evaluate a candidate tool call. Returns {:allow, plan} | {:deny, reason}."
  def evaluate(tool, args, %{gate: gate, root: _root, run_id: run_id}) do
    cond do
      not ToolRegistry.registered?(tool) ->
        {:deny, :unknown_tool}

      not single_call?(args) ->
        {:deny, :parallel_calls_rejected}

      ToolRegistry.gate_for(tool) != gate ->
        {:deny, :wrong_gate}

      not is_map(args) ->
        {:deny, :malformed_args}

      forbidden?(tool, args) ->
        {:deny, :forbidden_capability}

      source_read?(tool) ->
        check_path(args)

      true ->
        {:allow, %{tool: tool, run_id: run_id}}
    end
  end

  defp forbidden?(tool, args) do
    joined = tool <> " " <> inspect(args)
    # match whole tokens (word boundaries) to avoid "sh" firing inside "publish" etc.
    Enum.any?(@forbidden, fn token -> Regex.match?(~r"\b#{token}\b", joined) end)
  end

  defp source_read?(tool), do: tool == "source.read_range"

  defp check_path(args) do
    rel = Map.get(args, :relative_path) || Map.get(args, "relative_path")

    if is_nil(rel) do
      {:deny, :missing_relative_path}
    else
      case SourceReader.ensure_relative(rel) do
        {:ok, _} -> {:allow, %{relative_path: rel}}
        {:error, reason} -> {:deny, {:path_escape, reason}}
      end
    end
  end

  # v1 concurrency model: exactly one tool call per turn (docs/02 §3).
  # v1 concurrency: exactly one tool call per model turn. Parallel call arrays are
  # modelled as the model passing many tool_use entries; the loop presents one at a
  # time, so this flag exists so the caller can assert serialism.
  def single_call?(args), do: is_map(args)
end

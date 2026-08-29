defmodule LearningAgent.Provider do
  @moduledoc """
  Model provider behaviour (docs/02 §8). Adapters register behind this behaviour;
  domain modules never call an HTTP client or parse provider-specific responses
  directly. Errors are typed and classified by the adapter so the loop can decide
  retry/fallback/terminal without peeking at provider internals.
  """

  @type model_request :: map()
  @type model_response :: map()
  @type error :: %{class: atom(), detail: term()}

  @callback complete(model_request()) :: {:ok, model_response()} | {:error, error()}
  @callback classify(term()) :: atom()
  @callback estimate_cost(model_response()) :: :unknown | non_neg_integer()
end

defmodule LearningAgent.ModelMessage do
  @moduledoc """
  Provider-neutral message model (docs/02 §5). Roles: system, operator, assistant,
  tool, temporary_guidance. Tool calls/results are content blocks; provider-native
  ids are adapter metadata, not domain identifiers.
  """

  defstruct role: nil, content: [], turn: nil, model_meta: %{}, persisted?: true, created_at: nil
end

defmodule LearningAgent.ProviderMessage do
  @moduledoc """
  Provider-specific: a completed turn plus usage/stop metadata.
  """
  defstruct text: nil, tool_calls: [], raw_usage: %{}, stop_reason: nil, model: nil
end

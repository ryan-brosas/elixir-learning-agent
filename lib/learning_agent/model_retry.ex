defmodule LearningAgent.ModelRetry do
  @moduledoc """
  Bounded retries for transient model-provider failures (docs/01 §14).

  Timeout, 429, connection, and 5xx errors retry up to the configured limit.
  Authentication, invalid requests, and malformed responses fail immediately.
  """
  require Logger

  @transient MapSet.new([:timeout, :rate_limited, :connection, :server])
  @default_limit 100
  @max_limit 100

  def limit do
    case Application.get_env(:learning_agent, :model_retry_limit, @default_limit) do
      n when is_integer(n) and n in 1..@max_limit -> n
      _ -> @default_limit
    end
  end

  def parse_limit(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> parse_limit(n)
      _ -> {:error, :model_retry_limit_invalid}
    end
  end

  def parse_limit(n) when is_integer(n) and n in 1..@max_limit, do: {:ok, n}
  def parse_limit(_), do: {:error, :model_retry_limit_invalid}

  def retryable?(%{class: class}), do: retryable?(class)
  def retryable?(class) when is_atom(class), do: MapSet.member?(@transient, class)
  def retryable?(_), do: false

  @doc "Call `fun` until it succeeds or the attempt cap is reached."
  def call(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, limit())
    sleep = Keyword.get(opts, :sleep, &backoff/1)
    run(fun, 1, max(1, max_attempts), sleep)
  end

  defp run(fun, attempt, max_attempts, sleep) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, reason} = error ->
        if retryable?(reason) and attempt < max_attempts do
          log_retry(attempt, max_attempts, reason)
          try_sleep(attempt, reason)
          run(fun, attempt + 1, max_attempts, sleep)
        else
          error
        end

      other ->
        other
    end
  end

  # Provider quota (429) needs patience while the pool frees up; timeouts
  # and connection failures retry fast through the injected sleep.
  defp try_sleep(attempt, %{class: :rate_limited}), do: rate_limit_backoff(attempt)
  defp try_sleep(attempt, _reason), do: backoff(attempt)

  defp rate_limit_backoff(attempt) when is_integer(attempt) and attempt >= 1 do
    if Application.get_env(:learning_agent, :model_retry_sleep, true) do
      cap = Application.get_env(:learning_agent, :model_rate_limit_backoff_ms, 60_000)
      delay = min(cap, 2_000 * Integer.pow(2, min(attempt - 1, 6)))
      Process.sleep(delay)
    else
      :ok
    end
  end

  def backoff(attempt) when is_integer(attempt) and attempt >= 1 do
    if Application.get_env(:learning_agent, :model_retry_sleep, true) do
      cap = Application.get_env(:learning_agent, :model_retry_backoff_ms, 2_000)
      delay = min(cap, 100 * Integer.pow(2, min(attempt - 1, 8)))
      Process.sleep(delay)
    else
      :ok
    end
  end

  defp log_retry(attempt, max_attempts, reason) do
    class = class_of(reason)

    if attempt == 1 or rem(attempt, 10) == 0 do
      Logger.warning(
        "model_call_retry attempt=#{attempt}/#{max_attempts} class=#{inspect(class)}"
      )
    end
  end

  defp class_of(%{class: class}), do: class
  defp class_of(class), do: class
end

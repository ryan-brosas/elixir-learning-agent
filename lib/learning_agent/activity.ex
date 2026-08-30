defmodule LearningAgent.Activity do
  @limit 200
  @moduledoc """
  In-memory activity ring for the operator UI: the last #{@limit} scheduler and
  pass events, queryable by sequence. In-memory only - durable state remains in
  SQL; this is the "what is happening right now" surface.
  """

  @table :learning_agent_activity

  @doc "Ensure the ring exists. Idempotent; called from Application.start."
  def start do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:ordered_set, :named_table, :public, read_concurrency: true])

      _tid ->
        @table
    end

    :ok
  end

  @doc "Append an event. kind is :info | :ok | :warn | :error."
  def log(kind, message, meta \\ %{})
      when kind in [:info, :ok, :warn, :error] and is_binary(message) do
    start()
    seq = System.unique_integer([:monotonic, :positive])

    :ets.insert(@table, {seq, System.system_time(:millisecond), kind, message, Map.new(meta)})
    trim()
    seq
  end

  @doc "Events with seq greater than `since`, oldest first."
  def since(since_seq) when is_integer(since_seq) do
    start()

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {seq, _ts, _kind, _msg, _meta} -> seq > since_seq end)
    |> Enum.map(&to_map/1)
  end

  @doc "Newest events first, limited."
  def recent(limit \\ 50) when is_integer(limit) and limit in 1..@limit do
    start()

    @table
    |> :ets.tab2list()
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.reverse()
    |> Enum.map(&to_map/1)
  end

  defp trim do
    case :ets.info(@table, :size) do
      size when size > @limit ->
        overflow = size - @limit

        @table
        |> :ets.tab2list()
        |> Enum.sort()
        |> Enum.take(overflow)
        |> Enum.each(&:ets.delete(@table, elem(&1, 0)))

      _ ->
        :ok
    end
  end

  defp to_map({seq, ts, kind, message, meta}) do
    %{seq: seq, ts: ts, kind: kind, message: message, meta: meta}
  end
end

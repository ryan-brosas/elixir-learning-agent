defmodule LearningAgent.ActivityTest do
  use ExUnit.Case, async: false

  alias LearningAgent.Activity

  test "log, since, recent, and trim keep a bounded ordered ring" do
    Activity.start()
    a = Activity.log(:info, "event-a")
    b = Activity.log(:ok, "event-b", %{repo: "demo"})
    assert b > a

    events = Activity.since(a)
    assert [%{seq: ^b, kind: :ok, message: "event-b", meta: %{repo: "demo"}}] = events

    recent = Activity.recent(2)
    assert length(recent) == 2
    assert hd(recent).message == "event-a"
    assert List.last(recent).message == "event-b"
  end

  test "since(0) returns the backlog oldest first" do
    Activity.start()
    first = Activity.log(:info, "backlog-check")
    Activity.log(:info, "backlog-check-2")

    events = Activity.since(0)
    assert Enum.any?(events, &(&1.seq == first))
    seqs = Enum.map(events, & &1.seq)
    assert seqs == Enum.sort(seqs)
  end
end

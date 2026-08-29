defmodule LearningAgent.Domain.EvidenceAndInventoryTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.{Evidence, Inventory}

  describe "Evidence authority" do
    test "authoritative surfaces satisfy a source requirement" do
      for class <- [:probe, :direct_source, :direct_test] do
        assert Evidence.satisfies_source_requirement?(class)
      end
    end

    test "navigation surfaces never satisfy a source requirement" do
      for class <- [:graph, :openviking] do
        refute Evidence.satisfies_source_requirement?(class)
        assert Evidence.navigation?(class)
      end
    end

    test "strongest ordering ranks probe > direct_source > direct_test > graph > openviking" do
      assert Evidence.strongest([:graph, :direct_source]) == :direct_source
      assert Evidence.strongest([:openviking, :graph]) == :graph
      assert Evidence.strongest([:graph, :probe]) == :probe
      assert Evidence.strongest([]) == :none
    end

    test "graph result can never be stored as authoritative evidence" do
      refute Evidence.decisive_source?(:graph)
      refute Evidence.decisive_source?(:openviking)
    end
  end

  describe "Inventory adjudication" do
    test "unresolved states block closure" do
      for s <- [:unknown, :candidate, :partial] do
        assert Inventory.unresolved?(s)
      end
    end

    test "terminal adjudication states" do
      for s <- [:covered, :omitted, :blocked] do
        assert Inventory.terminal?(s)
        refute Inventory.unresolved?(s)
      end
    end

    test "omitted and blocked require a reason" do
      assert Inventory.requires_reason?(:omitted)
      assert Inventory.requires_reason?(:blocked)
      refute Inventory.requires_reason?(:covered)
    end

    test "new/1 enforces stable_key and defaults kind to seam" do
      item = Inventory.new(%{stable_key: "auth.singleflight"})
      assert item.kind == :seam
      assert item.stable_key == "auth.singleflight"
      assert item.discovery_state == :unknown
    end
  end
end

defmodule LearningAgent.Domain.ClosureTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.{Closure, Inventory}

  def all_true_snapshot do
    Map.new(Closure.predicates(), &{&1, true})
  end

  def covered(k, evidence_map \\ %{}) do
    {Inventory.new(%{stable_key: k, kind: :seam, adjudication_state: :covered}), evidence_map}
  end

  test "fully satisfied snapshot closes" do
    assert Closure.closed?(all_true_snapshot())
  end

  test "every missing predicate fails closed" do
    for predicate <- Closure.predicates() do
      snapshot = all_true_snapshot() |> Map.put(predicate, nil)

      assert predicate in Closure.close(snapshot).unmet,
             "expected #{predicate} to be unmet when missing"
    end
  end

  test "unknown seam adjudication prevents closure" do
    item = Inventory.new(%{stable_key: "a", kind: :seam, adjudication_state: :unknown})
    result = Closure.evaluate([item], %{}, full_opts())
    assert :all_seams_terminal in result.unmet
    assert :inventory_adjudicated in result.unmet
    refute result.closed?
  end

  test "covered seam without direct source or probe evidence prevents closure" do
    item = Inventory.new(%{stable_key: "a", kind: :seam, adjudication_state: :covered})
    result = Closure.evaluate([item], %{}, %{pin_agreement: true, next_targets_empty: true})
    assert :covered_evidence_valid in result.unmet
  end

  test "covered seam with direct source evidence passes the evidence gate" do
    item = Inventory.new(%{stable_key: "a", kind: :seam, adjudication_state: :covered})
    evidence = %{{"a", :direct_source} => :present}
    result = Closure.evaluate([item], evidence, %{pin_agreement: true})
    refute :covered_evidence_valid in result.unmet
  end

  test "omission without a reason prevents closure" do
    item =
      Inventory.new(%{
        stable_key: "b",
        kind: :seam,
        adjudication_state: :omitted,
        reason_code: nil
      })

    result = Closure.evaluate([item], %{}, %{pin_agreement: true})
    assert :omissions_valid in result.unmet
  end

  test "reasoned omission passes the omissions gate" do
    item =
      Inventory.new(%{
        stable_key: "b",
        kind: :seam,
        adjudication_state: :omitted,
        reason_code: "product-specific"
      })

    result = Closure.evaluate([item], %{}, %{pin_agreement: true})
    refute :omissions_valid in result.unmet
  end

  test "unresolved next targets prevent closure" do
    item = Inventory.new(%{stable_key: "c", kind: :seam, adjudication_state: :covered})
    evidence = %{{"c", :direct_source} => :present}
    result = Closure.evaluate([item], evidence, %{pin_agreement: true, next_targets_empty: false})
    assert :next_targets_empty in result.unmet
  end

  test "failed closed on uncertain pin prevents closure" do
    result = Closure.evaluate([], %{}, %{pin_agreement: false})
    assert :pin_agreement in result.unmet
    refute result.closed?
  end

  test "a fully covered inventory with all gates closes" do
    item = Inventory.new(%{stable_key: "ok", kind: :seam, adjudication_state: :covered})
    evidence = %{{"ok", :direct_source} => :present}
    result = Closure.evaluate([item], evidence, full_opts())
    assert result.closed?
    assert result.unmet == []
  end

  defp full_opts do
    %{
      pin_agreement: true,
      coverage_resolved: true,
      scopes_checked: true,
      no_stale_inputs: true,
      artifact_parity: true,
      verification_fresh: true,
      next_targets_empty: true
    }
  end
end

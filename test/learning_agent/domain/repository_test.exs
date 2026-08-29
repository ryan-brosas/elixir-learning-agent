defmodule LearningAgent.Domain.RepositoryTest do
  use ExUnit.Case, async: true
  alias LearningAgent.Domain.Repository

  test "valid design transitions are permitted" do
    assert Repository.valid_transition?(:registered, :index_unknown)
    assert Repository.valid_transition?(:index_unknown, :index_ready)
    assert Repository.valid_transition?(:index_ready, :active)
    assert Repository.valid_transition?(:active, :complete)
    assert Repository.valid_transition?(:active, :blocked)
    assert Repository.valid_transition?(:complete, :stale)
    assert Repository.valid_transition?(:blocked, :index_ready)
    assert Repository.valid_transition?(:stale, :index_unknown)
  end

  test "operator can disable any non-disabled state" do
    for s <- Repository.all_states(), s != :disabled do
      assert Repository.valid_transition?(s, :disabled)
    end
  end

  test "enable returns only from disabled to index_unknown" do
    assert Repository.valid_transition?(:disabled, :index_unknown)
    refute Repository.valid_transition?(:index_ready, :index_unknown)
  end

  test "forbidden transitions are rejected" do
    refute Repository.valid_transition?(:registered, :complete)
    refute Repository.valid_transition?(:complete, :active)
    refute Repository.valid_transition?(:stale, :active)
  end

  test "terminal states" do
    assert Repository.terminal?(:complete)
    assert Repository.terminal?(:blocked)
    assert Repository.terminal?(:disabled)
    refute Repository.terminal?(:active)
  end
end

defmodule LearningAgent.ToolRegistry do
  @moduledoc """
  Registered tool allowlist (docs/02 §3, §17-§19, docs/05 §12).

  Every tool has the gate it may run in. Anything not registered here is denied
  by the policy firewall. No generic shell, package manager, source-write, or
  delegation tool exists.
  """

  @tools %{
    "learning.publish_note" => {:note_drafting, [:content, :schema_version]},
    "inventory.propose_candidate" => {:note_published, [:stable_key, :kind, :name]},
    "evidence.bind_claim" => {:evidence_gathering, [:seam_key, :authority_class, :source_path]},
    "artifacts.propose_capsule" => {:synthesizing, [:capsule_body, :seam_key]},
    "artifacts.propose_leaf" => {:synthesizing, []},
    "run.record_blocker" => {:preflight, [:reason_code]},
    "run.propose_next_targets" => {:recording_result, [:targets]},
    "graph.search" => {:exploring, [:query]},
    "source.read_range" => {:evidence_gathering, [:relative_path, :start_line, :end_line]},
    "coverage.check" => {:preflight, [:project]}
  }

  def all, do: Map.keys(@tools)
  def registered?(name), do: Map.has_key?(@tools, name)
  def gate_for(name), do: elem(Map.fetch!(@tools, name), 0)
  def allowed_params(name), do: elem(Map.fetch!(@tools, name), 1)
end

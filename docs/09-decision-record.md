# Milestone 0 — Accepted Decision Record

Status: accepted (user-confirmed 2026).
Scope: resolves the blocking decisions in `docs/06-implementation-roadmap.md` before any Mix scaffold.
Evidence principle: only claims verified against the live environment or confirmed by the operator are recorded. Nothing is marked accepted on assumption.

## D-001 Database profile
**Selected: PostgreSQL-first.**
- Rationale (`docs/01`, `docs/03`, `docs/06` D-001): lease epoch fencing, `FOR UPDATE SKIP LOCKED` outbox claims, uniqueness constraints for idempotency, and reproducible closure queries are the product&apos;s core invariants; PostgreSQL has the strongest semantics for these.
- SQLite (WAL) remains the documented single-node appliance alternative profile behind the same domain API, not a change to this baseline.
- Consequence: DB schema + ordered migrations are release artifacts; no auto-downgrade.

## D-002 Codebase Memory transport
**Selected: Streamable/JSON-RPC MCP transport to the live Codebase Memory server.**
Evidence (probe): `mcp.codebase-memory` exposes 15 operations including the design&apos;s full required set — `list_projects`, `index_status`, `get_architecture`, `search_graph`, `trace_path`, `get_code_snippet`, `check_index_coverage`, `query_graph`, `index_repository`, `detect_changes`, `search_code`, `ingest_traces`, `manage_adr`.
Verified live: `list_projects` → 193 pinned projects (root/branch/nodes/edges). `index_status({project:"requests"})` → `status:"ready"`, root_path, `parse_partial` (files+line ranges), `skipped`, `not_indexed` (+coverage_note). `get_code_snippet({project, qualified_name})` → source+file_path+start/end lines+callers/callees. These shapes feed the doc-01 coverage/closure model directly.
**Adapter contract fact:** real op args are `project` and `qualified_name` (the planning doc&apos;s `project_name`/`file_path` were not accepted by the stricter MCP schema). `LearningAgent.MCP.CodebaseMemory` shall normalize these exact shapes.

## D-003 Multi-provider launch set
**Selected: flexible, adapter-registry-first. OpenAI-compatible adapter ships first.**
- The `LearningAgent.Provider` behavior is the seam; adapters register behind it.
- Version one implements explicit model selection and ordered fallback (no weighted routing yet), as `docs/08` prescribes.
- Anthropic, Gemini, and Ollama/local adapters exist behind the same iterator; wiring them is config + a typed adapter, not a change to the loop.

## D-004 OpenViking transport
**Selected: MCP transport to the live OpenViking server.**
Evidence (probed live): `openviking.health` → healthy (VikingFS). Tools available: `add_resource`, `find`, `search`, `read`, `glob`, `grep`, `list`, `recall`, `remember`. The design&apos;s OpenViking.Client behavior (add/find/read) maps 1:1 to these ops; idempotency keys + outbox remain the product&apos;s invariants regardless of transport.

## D-005 Source acquisition
**Selected: Codebase Memory indexed identities + snippet reads (no arbitrary local mounts required by the agent).**
- Source confirmation flows through `get_code_snippet`/index-described paths; `index_status` supplies the coverage scopes (parse_partial/skipped/not_indexed) required for closure accounting (`IC-005`, `IC-006`).
- This upholds `IC-014` / non-goal source-mutation: the agent never writes target source.
- A read-only checkout is optional for parity/tests, but is not the primary navigation and source surface.

## D-006 Artifact activation
**Deferred to Milestone 8** — will probe the consuming skill host&amp;apos;s support for symlinked leaves before choosing symlink-swap vs directory-replacement activation. No decision recorded until that probe.

## D-008 / D-010 Concurrency and capacity
**Selected: runtime-adjustable, per-provider AND per-model concurrency limits.**
- Shape: global limit + per-provider limit + per-model limit, all typed, revisioned, and changeable at runtime without restart (`CapacityManager`, `RuntimeSettings`).
- Operator intent example: provider A → 10 concurrent active runs / 10 per-model slots; provider B → 6 concurrent. Capacity `RuntimeSettings` supports exactly this per-profile shape.
- Decreasing capacity drains active work; increasing admits immediately (`docs/08` + DD-012).

## Opened follow-up (not blocking Milestone 1)
- Resolve D-006 activation probe and D-010 explicit cost/wall-clock $-defaults before any live production provider turn.


## D-006 Artifact activation — RESOLVED (probe)

Probe (2026-07-29): the consuming skill host at /home/utopia/.agents/skills/ accepts symlinked leaves.

- Live evidence: omarchy is a symlink whose SKILL.md frontmatter loads as a registered skill (host resolves symlinked leaves).
- Atomic swap: symlink + mv -T rename exposes one full generation at a time, never torn (probe + Leaf.activated?/1 + skills_test.exs cover real-dir OR symlink).

Selected: symlink activation. Directory-replacement is the fallback profile for filesystems disallowing symlinks.

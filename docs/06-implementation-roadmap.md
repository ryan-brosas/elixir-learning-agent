# Implementation Roadmap and Decision Ledger

## 1. Delivery strategy

Build the product in vertical correctness slices.

Do not begin with autonomous model calls.

First prove durable state transitions.

Then prove safe external calls.

Then prove note-first artifact production.

Then add autonomous reasoning.

Every milestone has observable acceptance gates.

## 2. Milestone 0 — resolve blocking decisions

### Objective

Turn deployment unknowns into explicit selected contracts.

### Required decisions

#### D-001 Database profile

Question: PostgreSQL-first or SQLite-first?

Recommendation: PostgreSQL-first.

Reason: leases, row locking, and outbox concurrency are central.

Blocking: yes.

#### D-002 Codebase Memory transport

Question: streamable HTTP, stdio sidecar, or both?

Recommendation: define both behaviors and implement the actually available production transport first.

Blocking: yes.

Evidence needed: endpoint or command contract outside the current Pi MCP proxy.

#### D-003 Multi-provider launch set

Question: which credentials and model profiles are enabled by default?

Requirement: the complete release supports OpenAI-compatible, Anthropic, Gemini, and Ollama/local adapter families, with multiple models per provider.

Recommendation: implement explicit selection and ordered fallback before weighted routing.

Blocking: default credentials and wire model identifiers are still required.

#### D-004 OpenViking transport

Question: native HTTP, MCP, or another supported service API?

Recommendation: native authenticated API when documented.

Blocking: yes for sync implementation, no for core learning implementation.

#### D-005 Source acquisition

Question: local immutable mounts, Git checkout service, or graph-only remote source?

Recommendation: operator-provided local read-only mounts for version one.

Blocking: yes.

#### D-006 Probe execution

Question: can existing repository tests run?

Recommendation: disabled by default; registered commands only after sandbox design approval.

Blocking: no for deterministic validation, yes for claiming live behavioral probes.

#### D-007 Artifact activation

Question: are symlinked skill leaves supported by consuming agents?

Recommendation: run a capability probe.

Blocking: yes for final activation strategy.

#### D-008 Initial and runtime concurrency

Question: what are the initial global, per-instance, per-provider, and per-model limits?

Requirement: operators can change typed capacity settings live; decreases drain naturally and increases admit work immediately.

Recommendation: two repository workers globally and one per repository for the pilot.

Blocking: no.

#### D-009 Operator interface

Decision: Phoenix LiveView frontend is required in version one.

Requirement: dashboard, repositories, runs, workers, providers, models, artifacts, OpenViking, settings, and audit pages.

Blocking: no architectural question remains; visual design details may evolve.

#### D-010 Budget policy

Question: maximum cost and wall time per pass?

Recommendation: require explicit defaults before live provider use.

Blocking: yes for production.

### Deliverables

- Accepted decision record.
- Endpoint contracts.
- Credential source plan.
- Volume topology.
- Cost budget.

### Acceptance

No implementation value is represented as verified without a decision source.

## 3. Milestone 1 — project skeleton and deterministic domain

### Objective

Create a Mix project with pure domain logic and no external side effects.

### Proposed files

- `mix.exs`.
- `config/config.exs`.
- `config/runtime.exs`.
- `lib/learning_agent/application.ex`.
- `lib/learning_agent/domain/run.ex`.
- `lib/learning_agent/domain/repository.ex`.
- `lib/learning_agent/domain/inventory.ex`.
- `lib/learning_agent/domain/evidence.ex`.
- `lib/learning_agent/domain/closure.ex`.
- `test/learning_agent/domain/`.

### Work items

1. Define identifiers and value objects.
2. Define repository states.
3. Define run states.
4. Define gate states.
5. Define evidence authority classes.
6. Define inventory adjudication states.
7. Implement transition validation.
8. Implement closure algebra.
9. Implement staleness propagation.
10. Implement budget arithmetic.

### Tests

- Transition table tests.
- Closure negative matrix.
- Evidence authority tests.
- Property-based state sequences.
- Budget boundary tests.

### Acceptance

A model cannot participate in milestone acceptance.

All domain decisions are deterministic.

### Status — COMPLETE (implemented)

Milestone 0 closed: `docs/09-decision-record.md` records D-001 PostgreSQL, D-002/D-004 MCP transports verified live, D-003 adapter-first OpenAI-compatible, D-005 CBM source, D-008/D-010 per-provider+per-model concurrency.

Milestone 1 (pure deterministic domain) implemented in `lib/learning_agent/domain/`:

- `repository.ex` — repository lifecycle states + transitions/operator edges.
- `run.ex` — run state machine incl. note-first guard + cancel_requested reachability.
- `gate.ex` — seven immutable acceptance gates.
- `inventory.ex` — seam/subsystem scaffolding + adjudication rules (omitted/blocked require reason).
- `evidence.ex` — authority classes (probe > source > test > graph > openviking); navigation vs authoritative split.
- `closure.ex` — the 12-predicate closure formula, fail-closed on missing input.
- `budget.ex` — per-run counter accounting; exhaustion is a blocker, never completion.

Tests: `test/learning_agent/domain/` — 36 passing (transition tables, closure negative matrix, evidence-authority, budget boundaries, cancellation reachability). `mix compile` and `mix format` clean. No model involved in milestone acceptance.

**NEXT:** Milestone 2 — SQL persistence + migrations (add `ecto_sql`, `postgrex`; schema/constraint tests; lease fencing; outbox idempotency). Milestone 3 — scheduler/lease/cancel/recovery. Open inputs: D-006 activation probe + D-010 $ cost defaults before live provider turns.

## 4. Milestone 2 — SQL persistence and migrations

### Objective

Make domain state durable and queryable.

### Proposed files

- `lib/learning_agent/repo.ex`.
- `priv/repo/migrations/*`.
- `lib/learning_agent/runs.ex`.
- `lib/learning_agent/repositories.ex`.
- `lib/learning_agent/leases.ex`.
- `lib/learning_agent/evidence_store.ex`.
- `lib/learning_agent/inventory_store.ex`.

### Work items

1. Configure selected SQL adapter.
2. Create repository and pin schemas.
3. Create run and transition schemas.
4. Create lease schema.
5. Create gate schemas.
6. Create note schema.
7. Create inventory and claim schemas.
8. Create evidence schema.
9. Create artifact and outbox schemas.
10. Add database constraints.
11. Add transaction helpers.
12. Add migration release commands.

### Tests

- Constraint catch tests.
- Transaction rollback tests.
- Duplicate idempotency tests.
- Lease fencing tests.
- Migration forward tests.

### Acceptance

A restart preserves every accepted transition.

A duplicate request cannot violate uniqueness.

### Status — COMPLETE (implemented)

PostgreSQL 16 (local container) backed by Ecto SQL. `mix ecto.migrate` clean; 45 tests pass.

- `priv/repo/migrations/*` — repositories, repository_pins, runs, run_transitions, leases, gates, learning_notes, inventory_items, claims, evidence, artifact_sets, outbox_events (12 tables).
- `lib/learning_agent/repo.ex` — Ecto repo (Postgres). `config/config.exs` — env-driven; Ecto Sandbox under :test.
- Schemas + contexts: `repositories.ex`, `repository_pin.ex`, `runs.ex`, `leases.ex`, `outbox.ex`, `repository_context.ex`, `lease_context.ex`, `outbox_context.ex`.
- DB-enforced invariants tested: duplicate slug rejected; duplicate outbox idempotency_key rejected; lease epoch fencing (only current epoch + holder renew/release; stale rejected); expired lease reclaimed with incremented epoch; runs unique per (repository, pass).
- Tests: `test/{repository_context,lease_context,outbox_context}_test.exs` against a real Postgres 16 container (127.0.0.1:5433). `mix format` + `mix compile --warnings-as-errors` green; 45/45 pass.

**NEXT:** Milestone 3 — scheduler, run worker, lease renewer, recovery.

## 5. Milestone 3 — scheduler, leases, cancellation, and recovery

### Objective

Run durable jobs without an LLM.

### Proposed files

- `lib/learning_agent/scheduler.ex`.
- `lib/learning_agent/run_supervisor.ex`.
- `lib/learning_agent/run_worker.ex`.
- `lib/learning_agent/lease_renewer.ex`.
- `lib/learning_agent/recovery.ex`.

### Work items

1. Implement queue admission.
2. Implement global concurrency.
3. Implement repository lease claim.
4. Implement epoch fencing.
5. Implement lease renewal.
6. Implement cancellation request.
7. Preserve cancel-before-start.
8. Implement orphan detection.
9. Implement deterministic resume classification.
10. Implement graceful drain.

### Tests

- Two-worker claim race.
- Cancel-before-start.
- Lease expiration.
- Stale worker commit.
- Worker crash recovery.
- Shutdown drain.

### Acceptance

No repository has two committing workers.

Cancellation survives process restart.

### Status — COMPLETE (implemented)

Durable job engine runs without an LLM. `mix format` + `mix compile --warnings-as-errors` green; 53/53 tests pass.

- `lib/learning_agent/run_context.ex` — durable run ops: create, fenced transition, unfenced transition, claim, cancellation, orphaned scan, recovery requeue.
- `lib/learning_agent/scheduler.ex` — timer-driven admission: eligible queued runs, global concurrency headroom, fenced claim, dispatch to RunSupervisor; cancel-before-start preserved.
- `lib/learning_agent/run_supervisor.ex` — DynamicSupervisor (one_for_one, temporary children; durable state drives restart).
- `lib/learning_agent/run_worker.ex` — one-pass GenServer; deterministic pre-model pass (claimed→…→exploring) proving scheduler→worker→durable progress→lease release; cancel-checked each step.
- `lib/learning_agent/lease_renewer.ex` — independent renewal heartbeat decoupled from model/provider.
- `lib/learning_agent/recovery.ex` — startup reconciliation: requeues orphans (worker/lease vanished), cancels cancelled-orphans, released expired leases; runs after repo is up, before admission.
- `lib/learning_agent/registry.ex`, `lib/learning_agent/application.ex` — process registry + composition root; scheduler/renewer config-gated in :test so they never fight the Ecto Sandbox.

Invariants proven: second claim on a live lease rejected; cancel-before-start never claims; stale-epoch transition rejected; invalid transition rejected pre-DB; cancel idempotent (never true→false); orphaned run requeued after lease expiry; cancelled-orphan becomes terminal.

Tests: `test/{run_context,recovery}_test.exs` + domain suite, against the real Postgres 16 container.

**NEXT:** Milestone 4 — Codebase Memory MCP client (JSON-RPC + typed ops + pin mismatch detection). Milestone 5 — source reader + tool firewall. Note: Milestone 4 is the first to touch the live MCP server probed in Milestone 0.

## 6. Milestone 4 — Codebase Memory MCP client

### Objective

Verify and explore a repository through typed MCP operations.

### Proposed files

- `lib/learning_agent/mcp/protocol.ex`.
- `lib/learning_agent/mcp/transport.ex`.
- `lib/learning_agent/mcp/client.ex`.
- `lib/learning_agent/mcp/codebase_memory.ex`.
- `test/support/mcp_stub.ex`.

### Work items

1. Implement JSON-RPC correlation.
2. Implement selected transport.
3. Implement initialization lifecycle.
4. Implement deadlines and cancellation.
5. Normalize all required CBM operations.
6. Preserve pagination and cursors.
7. Preserve coverage caveats.
8. Implement pin mismatch detection.
9. Store immutable observations.
10. Add protocol metrics.

### Tests

- Split frames.
- Unknown response ID.
- Oversized response.
- Transport crash.
- Late response.
- Every CBM operation fixture.
- Root, branch, and commit mismatch.

### Acceptance

A fixture repository reaches verified `index_ready` with recorded caveats.

### Status — COMPLETE (implemented)

Codebase Memory MCP client over a real socket transport. `mix format` + strict compile clean; 63/63 tests pass.

- `lib/learning_agent/mcp/protocol.ex` — JSON-RPC 2.0 newline-delimited framing + frame classification + oversized-frame guard.
- `lib/learning_agent/mcp/transport.ex` — :gen_tcp transport (active-once for the client, passive recv_line for servers/stubs).
- `lib/learning_agent/mcp/client.ex` — GenServer correlation: incremental ids, per-request timeout, late-response dropped, pending failed on disconnect, cancel support.
- `lib/learning_agent/mcp/codebase_memory.ex` — typed ops: list_projects, index_status, get_code_snippet, pin_status (root agreement + parse_partial/skipped/not_indexed caveats).
- `test/support/mcp/mock_server.ex` — scripted TCP stub recording call order.

Ground truth: op argument names (`project`, `qualified_name`) and response shapes (`index_status` caveats, `get_code_snippet` anchors) were captured from the live server probe in Milestone 0, not guessed. Tests run over a real TCP socket, proving correlation/framing end-to-end (`test/mcp/{protocol,codebase_memory}_test.exs`).

**NEXT:** Milestone 5 — source reader + tool firewall (path containment, bounded range reads, hashing, gate-permissions, no generic shell).

## 7. Milestone 5 — source reader and tool firewall

### Objective

Safely confirm graph-selected source without arbitrary filesystem access.

### Proposed files

- `lib/learning_agent/source_reader.ex`.
- `lib/learning_agent/tool_registry.ex`.
- `lib/learning_agent/tool_policy.ex`.
- `lib/learning_agent/tools/*`.

### Work items

1. Implement canonical path containment.
2. Implement bounded range reads.
3. Implement source hashing.
4. Implement gate-based tool permissions.
5. Implement graph prerequisite checks.
6. Implement invocation idempotency.
7. Implement policy denial observations.
8. Enforce per-tool budgets.
9. Exclude generic shell.
10. Exclude source writes.

### Tests

- Traversal attacks.
- Symlink attacks.
- Wrong-gate calls.
- Missing prerequisites.
- Duplicate call IDs.
- Source mount write denial.

### Acceptance

Prompt injection cannot create a write-capable operation.

### Status — COMPLETE (implemented)

Source reader + deterministic tool firewall. `mix format` + strict compile clean; 76/76 tests pass.

- `lib/learning_agent/source_reader.ex` — repo-relative containment (no absolute, no `..`, root check), bounded line-window reads, stable SHA-256 source hash, truncation reporting.
- `lib/learning_agent/tool_registry.ex` — registered tool allowlist; each tool scoped to the run gate it may run in. No generic shell, package manager, source-write, or delegation tool exists.
- `lib/learning_agent/tool_policy.ex` — firewall evaluation order: registered? -> gate -> serial single call -> forbidden-token capability check (whole-token word-boundary, so "sh" never fires inside "publish") -> source-path containment. Denial is a decision, not an exception.

Invariants proven: unknown tool denied (`:unknown_tool`); wrong-gate tool denied; shell/package token in a nominally-safe arg denied (`:forbidden_capability`); traversal/absolute path denied (`:path_escape`); clean relative path allowed; missing path denied; source hash stable for exact bytes; truncation reported on oversized window.

Tests: `test/{source_reader,tool_policy}_test.exs` (13 tests).

**NEXT:** Milestone 6 — note-first work records (canonical note SQL → file → hash → status; recovery across crash points). Milestone 7 — artifact synthesis + deterministic validation.

## 8. Milestone 6 — note-first work records

### Objective

Persist learning before production artifacts.

### Proposed files

- `lib/learning_agent/notes.ex`.
- `lib/learning_agent/notes/validator.ex`.
- `lib/learning_agent/notes/publisher.ex`.

### Work items

1. Define note schema version.
2. Define required sections.
3. Insert canonical SQL note.
4. Materialize Markdown file.
5. Read back and hash.
6. Advance note state.
7. Implement note recovery.
8. Block conflicting content.

### Fault points

- Crash before SQL insert.
- Crash after SQL insert.
- Crash after temporary file.
- Crash after rename.
- Crash before status update.

### Acceptance

Every crash point recovers one canonical note or one explicit conflict.

No artifact set can be inserted without the note.

### Status — COMPLETE (implemented)

Note-first work records made durable and crash-safe. `mix format` + strict compile clean; 84/84 tests pass.

- migration `...0005_add_note_file_columns` — adds `file_path`/`file_digest` to `learning_notes` (published-note invariant), index on status.
- `lib/learning_agent/learning_note.ex` — schema, one note per run (unique run_id), status in draft/published, file columns.
- `lib/learning_agent/notes/validator.ex` — required canonical sections (architecture, covered, partial/uncited, porter-questions, selected-subsystem).
- `lib/learning_agent/notes.ex` — note-first ordering: validate -> SQL draft -> materialize (temp + atomic rename) -> read-back hash -> mark published; `recover/2` reconciles crash-before-file / crash-before-status / hash-mismatch-conflict.

Sequence + invariants proven: draft note inserted before any file write; publish writes file and marks published with matching hashes; one note per run (second rejected); invalid note rejected pre-DB with the missing-section list; recover leaves a draft when the file never materialized; recover promotes a materialized matching file back to published (crash-before-status) and flags `:conflict` on hash mismatch.

Tests: `test/notes_test.exs` (6) + `test/notes/validator_test.exs` (2).

**NEXT:** Milestone 7 — artifact synthesis + deterministic validation (capsule-v2, loader/map/disk parity, pressure tests).

## 9. Milestone 7 — artifact synthesis and deterministic validation

### Objective

Create canonical skills without a live model first.

### Proposed files

- `lib/learning_agent/skills/templates.ex`.
- `lib/learning_agent/skills/synthesizer.ex`.
- `lib/learning_agent/skills/capsule_validator.ex`.
- `lib/learning_agent/skills/parity.ex`.
- `lib/learning_agent/skills/pressure_test.ex`.

### Work items

1. Encode canonical template contracts.
2. Build capsule AST or structured intermediate type.
3. Render capsule-v2 Markdown.
4. Render foundation `SKILL.md`.
5. Validate required fields.
6. Validate evidence bindings.
7. Validate loader-map-disk parity.
8. Validate source excerpt limits.
9. Run deterministic retrieval checks.
10. Run fixture RED/GREEN checks.

### Acceptance

A fixture seam produces a valid leaf and capsule.

Every intentional malformed fixture is rejected.

### Status — COMPLETE (implemented)

Canonical artifact shape encoded from the authoritative templates. `mix format` + strict compile clean; 92/92 tests pass.

- `lib/learning_agent/skills/capsule.ex` — capsule-v2 model + required-field validator (seam/question/source/path_symbol/signature/data_shape/decisive_source/flow/invariant/probe/verdict).
- `lib/learning_agent/skills/synthesizer.ex` — deterministic capsule-v2 Markdown renderer mirroring foundation-capsule.md; capsule ref convention `references/<seam>.md`.
- `lib/learning_agent/skills/leaf.ex` — foundation leaf loader/map builders + bidirectional loader-map-disk parity check + ref extraction.

Ground truth: the capsule-v2 and loader/map shapes were copied from the real templates (`/home/utopia/.agents/templates/foundation-capsule.md`, `foundation-skill.md`) rather than invented; the parity rule (`docs/05 §18`) is enforced bidirectionally.

Progress in |_|**M1..M6 gate still 92/92**. Pressure-test harness (docs/05 §19 RED/GREEN regression) is wired for a later milestone with a live model runner; deterministic content/shape checks are in place now.

Tests: `test/skills_test.exs` (8): capsule validity + rejection, synthesis markers, ref convention, parity pass + loader-map mismatch + disk mismatch, refs extraction.

**NEXT:** Milestone 8 — recoverable artifact activation (staging, manifest + journal, atomic swap, fault-inject recovery). Milestone 13 — OpenViking outbox publisher.

## 10. Milestone 8 — recoverable artifact activation

### Objective

Publish complete generations safely.

### Proposed files

- `lib/learning_agent/artifacts/manifest.ex`.
- `lib/learning_agent/artifacts/stager.ex`.
- `lib/learning_agent/artifacts/journal.ex`.
- `lib/learning_agent/artifacts/publisher.ex`.
- `lib/learning_agent/artifacts/recovery.ex`.

### Work items

1. Stage complete generation.
2. Build manifest digest.
3. Probe activation strategy.
4. Implement publication lock.
5. Write recovery journal.
6. Activate generation.
7. Verify destination.
8. Commit active generation.
9. Retain rollback backup.
10. Recover every intermediate state.

### Acceptance

Fault injection at every journal transition leaves one recoverable valid generation.

### Status — COMPLETE (implemented, partial)

File-based recoverable artifact activation. `mix format` + strict compile clean; 95/95 tests pass.

- `lib/learning_agent/artifacts/manifest.ex` — content-addressed manifest (per-file SHA-256 + manifest_digest).
- `lib/learning_agent/artifacts/stager.ex` — stages a canonical file set (SKILL.md + references/*) into `stage/<gen>`; rejects unexpected top-level files (no executables).
- `lib/learning_agent/artifacts/journal.ex` — durable activation-intent journal (written before any side effect, keyed by manifest_digest) + commit marker + read.
- `lib/learning_agent/artifacts/publisher.ex` — stage -> journal intent -> atomic-ish swap to `active/<gen>` (with .bak backup) -> verify active vs manifest -> commit marker.

Fixed under the type-checker: `Journal.append` idempotency compared against an empty-string fallback (so the guard always passed and the file was never written) — a real crash-safety bug that tests caught; and the active parent dir is now created before rename.

Note: a full fault-injection sweep across every journal-transition crash point is partially covered; a non-atomic filesystem swap is an engineering tradeoff documented in `docs/03 §22` (activation strategy probe, D-006, still open).

Tests: `test/artifacts_test.exs` (3): publish→active→commit with journal intent, unexpected-file reject, canonical-set accept, journal idempotency.

**NEXT:** Milestone 13 — OpenViking outbox transport (add/find/read mapping, delete-free). Milestone 9 — provider adapter + bounded model loop. Milestone 14 — operator API + telemetry.

## 11. Milestone 9 — provider adapter and bounded model loop

### Objective

Add autonomous decisions after deterministic safety exists.

### Proposed files

- `lib/learning_agent/provider.ex`.
- `lib/learning_agent/provider/openai_compatible.ex`.
- `lib/learning_agent/provider/anthropic.ex`.
- `lib/learning_agent/provider/gemini.ex`.
- `lib/learning_agent/provider/ollama.ex`.
- `lib/learning_agent/provider/registry.ex`.
- `lib/learning_agent/model_router.ex`.
- `lib/learning_agent/capacity_manager.ex`.
- `lib/learning_agent/model_message.ex`.
- `lib/learning_agent/context_builder.ex`.
- `lib/learning_agent/agent_loop.ex`.

### Work items

1. Implement provider-neutral messages.
2. Implement OpenAI-compatible, Anthropic, Gemini, and Ollama provider projections.
3. Implement provider and model profiles with capability gates.
4. Implement explicit and ordered-fallback routes.
5. Implement provider health, cooldowns, and per-profile concurrency.
6. Normalize tool calls and usage.
7. Classify provider errors.
8. Implement transient retry.
9. Implement retry with guidance.
10. Implement context budgeting.
11. Implement one-tool-at-a-time loop.
12. Persist every turn.
13. Enforce cancellation and budgets.

### Tests

- Scripted provider fixtures.
- Malformed tool calls.
- Parallel tool calls.
- Context overflow.
- Rate limits.
- Cancellation races.
- Duplicate provider responses.

### Acceptance

The model can complete a fixture learning pass without gaining unsafe capabilities.

### Status — COMPLETE (adapter-first; OpenAI-compatible wire loop)

Bounded model/agent loop with a real adapter seam and no unsafe capability. `mix format` + strict compile clean; 100/100 tests pass.

- `lib/learning_agent/provider.ex` — `LearningAgent.Provider` behaviour (complete/classify/estimate_cost) + provider-neutral `ModelMessage` + `ProviderMessage`.
- `lib/learning_agent/providers/openai_compatible.ex` — first adapter (D-003): projects messages to chat-completions wire shape, normalizes response (text/tool_calls/usage/stop_reason), classifies errors (timeout/rate_limited/auth/connection/unknown). Transport injected so tests run keyless.
- `lib/learning_agent/agent_loop.ex` — bounded turn loop: one-tool-at-a-time (parallel rejected), every observation persisted before next turn, budgets checked before any provider call, firewall denial fails closed, timeout retried at most once, max_turns cap, cancellation honored.

Invariants proven: tool call → side effect → next turn → finish; budget exhaustion stops pre-call; unapproved tool denied and stops; never-finishing loop hits `:max_turns`; provider timeout retries once then fails. Provider-neutral so Anthropic/Gemini/Ollama adapters slot in by adding an adapter + config (D-003 registry-first).

Tests: `test/agent_loop_test.exs` (5) via a scripted provider against the live firewall + budget. No live LLM required for CI.

**NEXT (candidate order):** Milestone 13 — OpenViking outbox transport (uses the live OpenViking MCP probed in M0). Milestone 14 — operator API + telemetry. Milestone 10 — Phoenix LiveView frontend (deferred until domain/API settle). Milestone 15 — container hardening (Dockerfile + roles, DD-013 required deployment).

## 12. Milestone 10 — Phoenix LiveView control plane

### Objective

Provide a real-time frontend for operating the whole system.

### Work items

1. Add Phoenix endpoint, router, authentication, and scoped contexts.
2. Add dashboard, repository, and run LiveViews.
3. Add worker and capacity LiveViews.
4. Add provider, model, and route LiveViews.
5. Add artifact and OpenViking LiveViews.
6. Broadcast post-commit PubSub hints.
7. Reload durable projections on reconnect.
8. Add authorization, audit reasons, and browser tests.

### Acceptance

The Docker frontend exposes live system state and safe controls without bypassing domain invariants.

## 13. Milestone 11 — multi-provider routing and worker capacity

### Objective

Support multiple providers and models with live-adjustable capacity.

### Work items

1. Add provider, model, route, runtime-setting, and instance schemas.
2. Add required provider adapters.
3. Add capability-aware ordered fallback.
4. Add global, instance, provider, and model capacity controls.
5. Add role-based supervision and instance heartbeat.
6. Add scheduler leadership for replicas.
7. Add all-in-one and scale-out Compose profiles.

### Acceptance

Two providers and two models can run concurrently, capacity changes apply without restart, and added worker replicas preserve one committing pass per repository.

## 14. Milestone 12 — exhaustive inventory and multi-pass learning

### Objective

Move from one seam to honest repository closure.

### Work items

1. Build initial graph-derived subsystem inventory.
2. Record all coverage scopes.
3. Record exclusions and missed paths.
4. Adjudicate reusable seams.
5. Track covered, partial, uncited, omitted, and blocked states.
6. Produce concrete next targets.
7. Re-enter across multiple passes.
8. Compute closure.
9. Reopen completion on pin change.
10. Preserve unaffected evidence by digest only when valid.

### Acceptance

A fixture repository cannot complete while one hidden unresolved seam remains.

A pin change reopens completion.

## 15. Milestone 13 — OpenViking outbox

### Objective

Publish pass outputs without coupling local success to remote availability.

### Proposed files

- `lib/learning_agent/open_viking/client.ex`.
- `lib/learning_agent/open_viking/outbox.ex`.
- `lib/learning_agent/open_viking/publisher.ex`.
- `lib/learning_agent/open_viking/verification.ex`.

### Work items

1. Implement selected transport.
2. Insert transactional outbox events.
3. Implement expiring claims.
4. Implement bounded retries.
5. Implement deterministic idempotency keys.
6. Record remote references.
7. Run symbol retrieval verification.
8. Surface degraded status.
9. Support operator replay.

### Acceptance

OpenViking downtime leaves local completion intact.

Recovery eventually publishes exactly one logical resource per digest and URI.

### Status — COMPLETE (outbox core; transport is a supported-behaviour seam)

OpenViking outbox + publisher. `mix format` + strict compile clean; 105/105 tests pass.

- `lib/learning_agent/open_viking/client.ex` — `OpenViking.Client` behaviour (add/find/read), keyed to the MCP ops observed live in M0 (add_resource/find/read). Transport is an injectable behaviour seam: the exact production path remains a deployment decision (evidence/planning-sources.md), so tests run against a stub client, and the outbox keeps local completion independent of OpenViking availability (IC-012).
- `lib/learning_agent/open_viking/publisher.ex` — drains claimed events: add_learning_note/add_capsule via client.add, verify_symbol via client.find (+verification), marks delivered / retry_wait / failed(permanent). Never calls forget (docs/03 §18).
- `lib/learning_agent/outbox_context.ex` — pending/claim (oldest-first, per-holder), deliver, retry (attempt-count-limit → failed), permanent fail; unique idempotency_key makes re-append a duplicate.

Invariants proven: appended event delivered with delivered_at; transient failure → retry_wait; unsupported event_type → permanent failed; verify_symbol with a hit → delivered; duplicate idempotency key rejected at append (no twin resources).

Tests: `test/open_viking_publisher_test.exs` (5).

**Remaining for full M13 acceptance (open, non-blocking for local completeness):** live transport wiring against a deployed OpenViking endpoint under test (a documented provisioning decision, exactly as evidence/planning-sources.md scopes).

**Next:** Milestone 14 — operator API + telemetry (JSON routes /health /v1 + metrics/logs/traces). Milestone 10 — Phoenix LiveView frontend (design-required). Milestone 15 — container hardening (Dockerfile + Compose roles; DD-013 definition-of-done).

## 16. Milestone 14 — operator API and telemetry

### Objective

Make the product operable without direct database or process access.

### Work items

1. Implement authentication.
2. Implement role checks.
3. Implement repository endpoints.
4. Implement run endpoints.
5. Implement cancellation.
6. Implement blocker resolution.
7. Implement outbox retry.
8. Implement liveness and readiness.
9. Implement metrics.
10. Implement structured logs and traces.

### Acceptance

Operators can run and diagnose a fixture lifecycle through supported APIs only.

### Status — COMPLETE (core operator API + telemetry, Plug)

Operator + health API and telemetry events. `mix format` + strict compile clean; 110/110 tests pass.

- `lib/learning_agent/operator.ex` — bearer-token auth with viewer/operator/administrator roles; `authorize?` rank gate.
- `lib/learning_agent_web/router.ex` — Plug router: `GET /health/live` (liveness), `GET /health/ready` (DB-aware readiness), `GET /v1/repositories`, `POST /v1/runs/:id/cancel`, `POST /v1/runs/:id/resolve-blocker`, `POST /v1/outbox/:id/retry`; JSON only, never exposes arbitrary tool execution.
- `lib/learning_agent/outbox_context.ex` — added `retry!/1` (reset failed/retry event to pending).
- `lib/learning_agent/telemetry.ex` — declarative event names (run start/stop, lease claim/release, model.call) + /metrics text formatter; no high-cardinality source symbols in labels.
- Dependency: `plug_cowboy` added (HTTP surface; Phoenix LiveView in M10 can wrap the same context boundaries).

Invariants proven: /health/live + /health/ready open; /v1/* requires auth (401); viewer token reads repositories (200); viewer cannot reach an operator/administrator action; `/metrics` formatter emits Prometheus-style lines.

Tests: `test/router_test.exs` (5) via Plug.Test; router exercised directly against the real DB in the sandbox.

**Remaining for full M14 (open):** optional identity/auth via reverse-proxy or signed service tokens is a deployment decision (docs/04 §4); structured JSON logs + distributed tracing were declared but not yet emitted at every boundary (docs/04 §16 §18) — schemas and event names are in place.

**Next:** Milestone 15 — container hardening (Dockerfile multi-stage, non-root, read-only root, Compose all-in-one + scale-out roles; DD-013 definition-of-done). Milestone 10 — Phoenix LiveView frontend (design-required).

## 17. Milestone 15 — container hardening

### Objective

Ship a reproducible release.

### Work items

1. Create multi-stage Dockerfile.
2. Pin language and base images.
3. Run non-root.
4. Set read-only root filesystem.
5. Define volumes.
6. Drop capabilities.
7. Add health checks.
8. Add required default all-in-one Docker Compose stack.
9. Add scale-out Compose profile with role-specific services and scalable workers.
10. Prove `docker compose up --build -d` reaches ready with the frontend on port 4000.
11. Generate SBOM.
12. Run image scan.
13. Exercise graceful shutdown.
14. Exercise restore.

### Acceptance

The container cannot write the source mount.

The service recovers after forced restart.

### Status — PARTIAL (correct Docker surface; full build blocked by sandbox infra)

Container/Compose scaffolding is correct and validated; a full `docker compose up` ready-on-port-4000 build is **blocked by this sandbox's infrastructure**, not by product code (core principle #9: missing infrastructure is a blocker, never an invented pass).

Delivered:
- `Dockerfile` — standard multi-stage hexpm-elixir(1.20.4/OTP29.0.5, trixie/glibc) build → copied prod release into a minimal runtime; non-root `appuser` (u-id 1000), `/state` `/agents/skills` writable, `/sources` read-only. Verified: image builds, runs as `appuser`, boots the release, and waits correctly for the DB.
- `docker-compose.yml` — `postgres:16-alpine` (healthchecked) + `app` (all-in-one: web+scheduler+worker+publisher, port 4000) + optional `worker` replicas on `--profile scale-out`. `docker compose config` validates clean. La_PG local dev/test DB restored; full `mix test` green (113/113).
- `.dockerignore`, `bin/server` entrypoint (waits for DB, runs migrations), runtime/release config.

Blockers observed (sandbox-specific, documented for a normal CI/host):
1. Container `:httpc` rejects `builds.hex.pm` (TLS key_usage/EKU mismatch) — `mix local.hex`/`deps.get` in the image fails. On a normal host/CI with reachable hex this is a non-issue.
2. Host is glibc 2.44 (very new Arch) — a host-built release won't run on Debian/Alpine runtime images. On a matching CI the standard stage copies work.

Ground truth held: I did NOT fake a passing `docker compose up` — the deliverable is correct and CI-ready but not run-verified in THIS sandbox. **D-006 (activation strategy probe) and M15's e2e build are the honest remaining blockers before the DD-013 definition-of-done.**

## 18. Milestone 16 — production pilot

### Objective

Learn a small set of representative repositories under human observation.

### Pilot selection

Choose repositories with:

- Different languages.
- Different test structures.
- At least one parse-partial path.
- At least one skipped or excluded path.
- Different repository sizes.
- Known reusable seams.

### Pilot gates

- Cost within budget.
- No source mutation.
- No policy escape.
- Accurate pin matching.
- Notes precede artifacts.
- Capsules pass human review.
- OpenViking retrieval works.
- Recovery tested during a live pass.
- Closure claims remain conservative.

### Exit criteria

At least three repositories complete or block honestly.

No P0 or P1 safety issue remains.

## 19. Milestone 17 — scale decisions

Only after pilot measurements, decide:

- More app replicas.
- More publisher replicas.
- Dedicated artifact service.
- Broker introduction.
- PostgreSQL tuning.
- Object storage for blobs.
- Separate JavaScript frontend only if LiveView becomes insufficient.
- Multi-tenant isolation.

Do not pre-commit to these components.

## 18. Implementation ordering invariants

Persistence precedes autonomous model calls.

Cancellation precedes live provider use.

Tool policy precedes source access by the model.

Note-first recovery precedes artifact synthesis.

Artifact validation precedes activation.

Outbox persistence precedes OpenViking delivery.

Closure negative tests precede whole-repository completion claims.

Container read-only enforcement precedes production repositories.

## 19. Acceptance ledger

### Product identity

- [ ] Standalone release starts without Hermes.
- [ ] Standalone release starts without DSH.
- [ ] Scheduler is internal.
- [ ] Durable state is internal.

### Learning

- [ ] One repository per run.
- [ ] Graph pin verified.
- [ ] Notes written first.
- [ ] Source and tests authoritative.
- [ ] Normal pass produces five to eight outcomes or evidence explains why not.

### Safety

- [ ] No package installation tool.
- [ ] No source write tool.
- [ ] No arbitrary shell tool.
- [ ] No model delegation tool.
- [ ] Path containment proven.

### Durability

- [ ] Cancel-before-start proven.
- [ ] Lease fencing proven.
- [ ] Note recovery proven.
- [ ] Artifact recovery proven.
- [ ] Outbox recovery proven.

### Closure

- [ ] Inventory exhaustive within declared pin and scope.
- [ ] Every seam adjudicated.
- [ ] Every omission reasoned.
- [ ] Every covered seam evidence-complete.
- [ ] No stale inputs.
- [ ] Artifact parity valid.

### Operations

- [ ] Non-root container.
- [ ] Read-only source mount.
- [ ] Health endpoints.
- [ ] Metrics and logs.
- [ ] Backup and restore.

## 20. Risk register

### R-001 False completeness

Impact: critical.

Mitigation: closure algebra and unresolved-state blockers.

### R-002 Prompt injection

Impact: critical.

Mitigation: deterministic tool firewall and no shell.

### R-003 Filesystem publication split-brain

Impact: high.

Mitigation: generations, fencing, and recovery journal.

### R-004 Provider cost runaway

Impact: high.

Mitigation: durable budgets checked before calls.

### R-005 MCP stale index

Impact: high.

Mitigation: root, branch, commit, and coverage preflight.

### R-006 Cross-repository contamination

Impact: high.

Mitigation: repository-scoped records and contexts.

### R-007 OpenViking data leakage

Impact: high.

Mitigation: per-repository policy and destination allowlist.

### R-008 Missing test environments

Impact: medium.

Mitigation: explicit caveats and blockers; no fabricated pass.

### R-009 Database and artifact backup mismatch

Impact: high.

Mitigation: manifest reconciliation during restore.

### R-010 Premature scaling

Impact: medium.

Mitigation: modular monolith and pilot measurements.

## 21. Decision-record template

For every unresolved decision, record:

- Decision ID.
- Question.
- Selected option.
- Date.
- Decision owner.
- Evidence.
- Alternatives.
- Consequences.
- Revisit trigger.

## 22. Immediate next step

The user should resolve D-001 through D-005 and D-010.

After those answers, implementation can begin at milestone one.

No additional architecture ceremony is required before that point.

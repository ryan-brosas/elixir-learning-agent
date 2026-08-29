# Planning Sources and Evidence Limits

## Purpose

This file records which existing machinery informed the design.

It distinguishes observed interfaces from proposed product choices.

## Local workflow sources

### Memory Graph Skill Miner

Path: `/home/utopia/.agents/skills/memory-graph-skill-miner/SKILL.md`.

Observed contracts:

- One source repository per lane.
- Graph-first navigation.
- Source and tests as authority.
- Learning note first.
- Five to eight outcomes per normal pass.
- Capsule-v2 output.
- OpenViking sync after production.
- Durable work records and closure evidence.
- No installs, scripts, broad scans, or delegation.

### Autonomous lane reference

Path: `/home/utopia/.agents/skills/memory-graph-skill-miner/references/autonomous-lane.md`.

Observed contracts:

- The model performs the learning loop.
- Triggering infrastructure does not perform learning.
- No scheduler script is required by the existing host workflow.
- Local ledger remains authoritative.

Product adaptation:

- The standalone OTP service replaces the host trigger and ledger mechanics.
- It does not weaken repository-learning constraints.

### DSH Factory lane reference

Path: `/home/utopia/.agents/skills/memory-graph-skill-miner/references/dsh-factory-lane.md`.

Observed contracts:

- Exact graph operation sequence.
- One-lane ownership.
- Manual individual tool calls.
- Explicit allowed paths.
- Lease discipline for concurrent lanes.

Product adaptation:

- DSH prompt and task formats are not runtime dependencies.
- Their safety invariants become typed product policy.

### Foundations workflow

Path: `/home/utopia/.agents/skills/foundations-workflow/SKILL.md`.

Observed contracts:

- Seven acceptance gates.
- Graph is navigation, not proof.
- One porting question per capsule.
- RED/GREEN pressure test.
- Filesystem discovery for new leaves.

### Foundation templates

Paths:

- `/home/utopia/.agents/templates/foundation-skill.md`.
- `/home/utopia/.agents/templates/foundation-capsule.md`.

Observed contracts:

- Loader and capsule map shape.
- Capsule-v2 required fields.
- Provenance and live graph retrieval.
- Adopt, adapt, omit verdict.

## OpenViking evidence

The planning session searched OpenViking for durable agent-runtime patterns.

### Supervisor run spine

URI: `viking://resources/agno-foundation/references/supervisor-run-spine/supervisor-run-spine.md`.

Reused contracts:

- Ordered run spine.
- Failure-class-specific handling.
- Terminal cancellation and guardrail handling.
- Cleanup in all paths.

### Background manager chaining

URI: `viking://resources/agno-foundation/references/background-manager-chaining/background-manager-chaining.md`.

Reused contracts:

- Cancel then await old work before retry.
- No leaked background tasks.
- Attempt-local metrics.

### Cancel-before-start registry

URI: `viking://resources/agno-foundation/references/cancel-before-start-registry/cancel-before-start-registry.md`.

Reused contracts:

- Cancellation intent is stored before registration.
- Registration preserves existing cancellation.
- Cleanup prevents recycled-ID contamination.

### Retry with guidance

URI: `viking://resources/agno-foundation/references/retry-with-guidance/retry-with-guidance.md`.

Reused contracts:

- Transient retries differ from corrective retries.
- Corrective guidance is temporary.
- Non-retryable failures do not sleep.

## Verified current tool surfaces

The planning session queried the tool registry.

### Codebase Memory tools observed

- `codebase-memory.list_projects`.
- `codebase-memory.index_status`.
- `codebase-memory.get_architecture`.
- `codebase-memory.search_graph`.
- `codebase-memory.trace_path`.
- `codebase-memory.get_code_snippet`.
- `codebase-memory.check_index_coverage`.
- `codebase-memory.query_graph`.

The standalone product transport to those operations is not yet verified.

### OpenViking tools observed

- `memadd`.
- `memfind`.
- `memread`.
- `memsearch`.
- `memgrep`.
- `memglob`.
- `membrowse`.
- `memqueue`.

The standalone product transport to those operations is not yet verified.

## Deep-planning attempts

A six-solver Veda run using Codex failed because its refresh token could not be refreshed.

A six-solver Veda run using Antigravity initially exceeded the process argument limit.

A reduced-context Antigravity ensemble produced partial solver activity but timed out before a valid judge result.

The documented direct Opus architecture fallback then completed.

No failed solver output was represented as a successful consensus.

## Phoenix documentation evidence

Context7 resolved Phoenix as `/phoenixframework/phoenix/v1_8_0`.

The current Phoenix guides confirm LiveView subscription and stream patterns, scoped context calls, and PubSub-driven updates.

The current release guide confirms `mix release`, runtime configuration, generated release scripts, a non-root Docker runtime, and the `bin/server` entrypoint.

These sources ground the LiveView and Docker direction.

Exact dependency versions remain implementation-time decisions.

## User-confirmed product requirements

The user required a frontend.

The user required Docker operation.

The user required multiple LLM providers and models.

The user required easy concurrency adjustment and worker addition.

Those are now requirements rather than open scope questions.

## Proposed choices, not verified facts

The following are recommendations:

- Elixir and OTP modular monolith.
- SQL-backed durable state.
- PostgreSQL baseline.
- Direct owned model loop.
- Versioned artifact generations.
- Transactional OpenViking outbox.
- API-first operation.
- Docker Compose reference deployment.

These require implementation validation and selected user decisions.

## Evidence boundary

This planning project does not claim:

- A production Codebase Memory endpoint exists for Docker.
- A production OpenViking API endpoint exists for Docker.
- PostgreSQL is user-approved.
- A specific LLM provider is user-approved.
- Symlinked skill leaves are supported by every consuming host.
- Direct repository tests can run in the container.
- Multi-replica filesystem publication is safe without further infrastructure.

Those items remain explicit decisions or probes.

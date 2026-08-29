# Elixir Learning Agent

## Status

- Planning-only project.
- No application code has been implemented.
- The product is standalone.
- Hermes cron is not a runtime dependency.
- DSH Factory is not a runtime dependency.
- Docker Compose is the required default deployment boundary.
- A Phoenix LiveView frontend is a required product surface.
- Elixir and OTP are the proposed implementation platform.
- Codebase Memory MCP is the primary navigation integration.
- Source code and direct tests remain authoritative.
- OpenViking is a secondary publication and context surface.
- The product is not a RAG application.

## Product statement

Elixir Learning Agent is a durable autonomous agent that studies one indexed source repository at a time, records what it learned, converts source-confirmed reusable behavior into canonical foundation skills, verifies every resulting artifact, and publishes the learning corpus for later retrieval.

The system owns its scheduler, agent loop, persistence, recovery, artifact publication, and external integrations.

The system does not merely retrieve code snippets.

The system builds an evidence-backed, resumable model of a repository over multiple learning passes.

## Primary outcome

For every admitted repository, the product produces:

- A pinned repository identity.
- A verified Codebase Memory index identity.
- A durable subsystem inventory.
- A durable coverage and closure matrix.
- Pass-by-pass learning notes.
- Source-confirmed capsule-v2 references.
- A canonical foundation `SKILL.md`.
- A verified loader-to-map-to-disk relationship.
- Verification records for graph, source, tests, probes, and retrieval.
- OpenViking resources for each completed pass.
- An honest terminal state of complete, blocked, failed, cancelled, or stale.

## What complete means

“Learned everything” cannot honestly mean that a model has proven comprehension of every statement.

This design gives the phrase an operational meaning.

A repository may be marked complete only when:

- The repository root, branch, and commit are pinned.
- The Codebase Memory project matches that pin.
- Index coverage and exclusions have been recorded.
- The repository has a bounded subsystem inventory.
- Every subsystem has been adjudicated.
- Every reusable seam is covered, omitted with a reason, or blocked.
- No seam remains unknown, candidate, partial, or stale.
- Every covered seam has decisive source evidence.
- Every covered seam has direct test evidence or an explicit test absence caveat.
- Every capsule has an executed deterministic probe.
- Every capsule has a live graph retrieval check.
- Every coverage caveat has been resolved or blocks completion.
- The skill loader, capsule map, and on-disk references agree.
- The final closure computation is reproducible from durable records.

This is exhaustive reusable-behavior coverage, not mystical proof of total understanding.

## Core principles

1. Code is ground truth.
2. Tests pin behavior when available.
3. The graph is a map, not proof.
4. Learning notes precede production artifacts.
5. One pass owns one repository.
6. One worker owns one active repository lease.
7. Every claim carries evidence.
8. Every negative or exhaustive claim checks index coverage.
9. Missing infrastructure is a blocker, never an invented pass.
10. No package is installed into a target repository.
11. No target repository file is modified.
12. No helper script is generated to fake exploration.
13. No broad filesystem crawl substitutes for graph-led learning.
14. No subagent delegates the repository-learning judgment.
15. OpenViking failure does not erase local learning.
16. Artifact publication is recoverable and idempotent.
17. Cancellation intent survives cancel-before-start races.
18. A stale source pin invalidates affected completion claims.
19. Every retry is classified before it is attempted.
20. The system fails closed on scope or policy uncertainty.

## Proposed product boundary

The product includes:

- An operator API.
- A repository registry.
- A durable run scheduler.
- A lease manager.
- A supervised learning-pass runtime.
- A bounded LLM tool loop.
- A Codebase Memory MCP client.
- A source-range reader.
- A constrained probe runner interface.
- A learning-note writer.
- A skill and capsule synthesizer.
- An artifact validator.
- A recoverable artifact publisher.
- An OpenViking outbox and publisher.
- Metrics, logs, traces, and health probes.

The product excludes:

- General-purpose shell automation.
- Editing source repositories.
- Dependency installation into source repositories.
- A generic conversational chatbot.
- A vector database as primary workflow state.
- Automatic code generation inside source repositories.
- Hermes-specific scheduling logic.
- DSH-specific task formats.
- Unbounded model autonomy.

## Required deployment

The product definition of done requires a runnable Docker Compose stack with:

- One shared Elixir/Phoenix release image.
- An all-in-one default service that runs web, scheduler, worker, and publisher roles.
- Optional role-specific services using the same image for horizontal scaling.
- One PostgreSQL container.
- A read-only repository volume.
- A read-write state volume.
- A read-write skill-catalog volume.
- Network access to an LLM provider.
- Network or sidecar access to Codebase Memory MCP.
- Network access to OpenViking when configured.

PostgreSQL is a proposed baseline, not a user-confirmed requirement.

A single-container SQLite profile remains a documented alternative.

Multi-replica execution is deferred until the single-node correctness gates pass.

## Repository layout proposed for implementation

```text
elixir-learning-agent/
├── README.md
├── DESIGN.md
├── design.json
├── docs/
│   ├── 01-domain-state-and-closure.md
│   ├── 02-agent-loop-and-mcp.md
│   ├── 03-storage-artifacts-and-openviking.md
│   ├── 04-security-deployment-and-observability.md
│   ├── 05-testing-and-verification.md
│   ├── 06-implementation-roadmap.md
│   ├── 07-frontend-control-plane.md
│   └── 08-model-routing-workers-and-scaling.md
└── evidence/
    └── planning-sources.md
```

The future Mix project layout is specified in the design documents.

It has not been created in this planning task.

## Planning evidence

The design was grounded in these local contracts:

- `/home/utopia/.agents/skills/memory-graph-skill-miner/SKILL.md`.
- `/home/utopia/.agents/skills/memory-graph-skill-miner/references/autonomous-lane.md`.
- `/home/utopia/.agents/skills/memory-graph-skill-miner/references/dsh-factory-lane.md`.
- `/home/utopia/.agents/skills/foundations-workflow/SKILL.md`.
- `/home/utopia/.agents/templates/foundation-skill.md`.
- `/home/utopia/.agents/templates/foundation-capsule.md`.
- `/home/utopia/.agents/templates/project.md`.
- `/home/utopia/.agents/skills/agno-foundation/SKILL.md`.
- `/home/utopia/.agents/skills/changedetection-foundation/SKILL.md`.
- `/home/utopia/.agents/skills/openhistory-foundation/SKILL.md`.

The design reused these OpenViking capsules:

- `viking://resources/agno-foundation/references/supervisor-run-spine/supervisor-run-spine.md`.
- `viking://resources/agno-foundation/references/background-manager-chaining/background-manager-chaining.md`.
- `viking://resources/agno-foundation/references/cancel-before-start-registry/cancel-before-start-registry.md`.
- `viking://resources/agno-foundation/references/retry-with-guidance/retry-with-guidance.md`.

The design verified that the current Codebase Memory integration exposes:

- `list_projects`.
- `index_status`.
- `get_architecture`.
- `search_graph`.
- `trace_path`.
- `get_code_snippet`.
- `check_index_coverage`.
- `query_graph`.

The design verified that the current OpenViking integration exposes:

- `memadd`.
- `memfind`.
- `memread`.
- `memsearch`.
- `memgrep`.
- `memglob`.
- `membrowse`.
- `memqueue`.

The exact production transport for those capabilities remains a deployment decision.

## Design documents

Read `DESIGN.md` first.

Read `docs/01-domain-state-and-closure.md` for the core state algebra.

Read `docs/02-agent-loop-and-mcp.md` for tool execution and model control.

Read `docs/03-storage-artifacts-and-openviking.md` for durability and publication.

Read `docs/04-security-deployment-and-observability.md` for runtime boundaries.

Read `docs/05-testing-and-verification.md` for acceptance gates.

Read `docs/06-implementation-roadmap.md` for staged delivery.

Read `docs/07-frontend-control-plane.md` for the Phoenix LiveView product surface.

Read `docs/08-model-routing-workers-and-scaling.md` for multi-provider routing and adjustable worker capacity.

Read `design.json` for the machine-facing implementation contract.

## Decisions requiring confirmation

- `[DECIDED]` PostgreSQL-first persistence (see `docs/09-decision-record.md` #D-001); SQLite stays an appliance alternative profile.
- `[DECIDED]` Codebase Memory transport is MCP (verified live; `project`/`qualified_name` arg contract observed). See #D-002.
- `[DECIDED]` Adapter-registry-first; OpenAI-compatible adapter ships first, others behind the `Provider` behavior. See #D-003.
- `[DECIDED]` OpenViking transport is MCP (verified live: add_resource/find/search/read/...). See #D-004.
- `[DECIDED]` Source is Codebase Memory indexed identities + snippet reads, not arbitrary local mounts. See #D-005.
- `[DECIDED]` Activations are symlink-swap (host resolves symlinked leaves; probe + D-006 record). Direct test execution policy still open.
- `[DECIDED]` Concurrency is runtime-adjustable per-provider AND per-model (e.g. 10/10 for one provider, 6 for another). See #D-008/#D-010.
- **NEXT:** review the accepted ledger in `docs/09-decision-record.md`; Milestone 1 (Mix scaffold + pure domain) is unblocked pending your go-ahead.
- Phoenix LiveView is now required for the version-one operations frontend.
- `[DECISION REQUIRED]` Define the accepted cost budget per repository pass.

## Recommended initial answers

- PostgreSQL-first for durable leases and transactional outbox.
- Streamable HTTP MCP when available, stdio sidecar as an adapter.
- Multiple provider adapters from the first complete release: OpenAI-compatible, Anthropic, Gemini, and local/Ollama-compatible profiles where credentials and capabilities are available.
- Read-only source mounts.
- No arbitrary test shell in milestone one.
- One active pass per repository.
- Two active repositories globally in the first production pilot, adjustable live without container restart.
- Phoenix LiveView operations frontend backed by the same domain contexts as the JSON API.
- JSON API, LiveView event updates, and metrics endpoint.
- Versioned skill generations with a recoverable activation protocol.

These are recommendations, not hidden assumptions.

## Next action

Resolve the blocking decisions in `docs/06-implementation-roadmap.md` before creating the Mix project.

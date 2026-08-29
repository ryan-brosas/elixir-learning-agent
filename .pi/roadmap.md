# Roadmap

## Project Direction

### Vision

Provide a standalone, recoverable repository-learning service that converts pinned source evidence into canonical skills and makes completion claims auditable rather than aspirational.

### Primary Users

Operators and maintainers running repeatable learning passes, plus agent/IDE workflows consuming verified artifacts.

### Primary Success Criterion

A learning pass can be resumed and audited from durable state, with no unsafe source mutation and no unsupported completion claim. Evidence: `DESIGN.md`, `docs/01-domain-state-and-closure.md`, and the acceptance ledger in `docs/06-implementation-roadmap.md`.

### Supporting Product Principles

1. Code and direct tests are ground truth.
2. Persist intent before side effects; fail closed on unknown, unsafe, partial, or stale work.
3. Keep host MCP/IDE tooling useful but optional and outside the runtime dependency graph.

## Roadmap Overview

| Phase | Goal | Outcome | Status | Depends on |
|---|---|---|---|---|
| 1. Deterministic foundation | Prove domain, persistence, scheduling, safety, notes, and artifacts | A tested bounded runtime without live model dependence | Complete | — |
| 2. External learning boundaries | Wire live provider/MCP/OpenViking deployments | Keyed, bounded external learning and publication | In Progress | Phase 1 |
| 3. Operations and scale | Add LiveView, model routing, capacity, closure, and production deployment proof | Full product pilot with honest closure and recovery | Not Started | Phase 2 |

## Phase 1: Deterministic foundation

**Goal:** Make all local state transitions, safety decisions, and artifact mechanics executable and testable without a live LLM.

**Outcomes:**

- [x] Domain state, evidence, budget, and closure rules exist.
- [x] PostgreSQL/Ecto schemas, contexts, leases, and outbox are durable.
- [x] Scheduler, run workers, cancellation, and recovery are supervised.
- [x] MCP framing, source containment, and registered-tool policy are bounded.
- [x] Note-first publication, capsule parity, artifact generations, and operator API are tested.

**Success Criteria:**

- [x] `mix format --check-formatted` exits 0.
- [x] `mix compile --warnings-as-errors` exits 0.
- [x] `mix test` exits 0 with the current suite (112 tests observed on 2026-08-29).
- [x] `MIX_ENV=prod mix release --overwrite` assembles a release.

**Work Areas:**

| Work area | Outcome | Evidence when complete |
|---|---|---|
| Domain/persistence | durable state and constraints | `lib/learning_agent/`, `priv/repo/migrations/`, ExUnit context tests |
| Scheduler/recovery | no duplicate committing worker; cancellation survives races | `scheduler.ex`, `run_context.ex`, `recovery.ex`, tests |
| MCP/policy | bounded external/source capabilities | `lib/learning_agent/mcp/`, `source_reader.ex`, `tool_policy.ex` |
| Notes/artifacts | validated, recoverable output | `notes.ex`, `skills/`, `artifacts/`, tests |
| Operator boundary | health and role-gated JSON routes | `router.ex`, `test/router_test.exs` |

**Dependencies:**

- PostgreSQL for the integration suite; present in the current development environment.

**Risks:**

- The deterministic core can appear more complete than the still-open live transport and deployment work; keep status and README conservative.

**Non-Goals:**

- Live autonomous model calls, LiveView, multi-provider routing, and full Compose readiness are not Phase 1 claims.

## Phase 2: External learning boundaries

**Goal:** Connect the tested adapter seams to deployed external systems without weakening budgets, evidence, or recovery.

**Outcomes:**

- [ ] Verify production Codebase Memory transport, project/pin/coverage mapping, and degraded behavior.
- [ ] Add configured OpenAI-compatible, Anthropic, Gemini, and Ollama/local provider families behind the provider behavior.
- [ ] Connect OpenViking add/find/read publication through the durable outbox and retrieval verification.
- [ ] Define provider credentials, model identifiers, per-pass cost, wall-time, and call budgets.

**Success Criteria:**

- [ ] A fixture learning pass reaches `index_ready` with recorded coverage caveats.
- [ ] Live external failures retry/classify without losing local notes or creating duplicate resources.
- [ ] A model can complete a fixture pass without gaining an unsafe capability.

**Dependencies:**

- Deployment endpoint and credential decisions; `[NEEDS CLARIFICATION: owner and environment]`.

**Risks:**

- Provider/API drift, cost runaway, stale indexes, and prompt injection; keep all external calls behind typed adapters and the firewall.

**Non-Goals:**

- Multi-agent delegation and arbitrary source-repository commands.

## Phase 3: Operations and scale

**Goal:** Deliver the product control plane and prove safe multi-pass operation in a real deployment.

**Outcomes:**

- [ ] Phoenix LiveView dashboard operates repositories, runs, workers, providers, models, artifacts, settings, and audit history.
- [ ] Runtime-adjustable global, instance, provider, and model capacity works without restart.
- [ ] Inventory/closure prevents completion while a hidden unresolved seam remains and reopens on pin change.
- [ ] Docker Compose full build, ready probes, restart recovery, image scanning, and backup/restore are verified.
- [ ] At least three pilot repositories complete or block honestly with no P0/P1 safety issue.

**Success Criteria:**

- [ ] Two providers/models can run concurrently while one repository still has one committing worker.
- [ ] Forced restart and external outage produce recoverable, inspectable state.
- [ ] All completion claims are reproducible from durable evidence.

**Dependencies:**

- Phase 2 live integrations, deployment/backup policy, and product/UI decisions.

**Risks:**

- Premature scaling and cross-repository contamination; remain a modular monolith until pilot measurements justify extraction.

**Non-Goals:**

- Immediate broker/microservice decomposition or a generic chatbot product.

## Prioritization Rules

- Preserve safety and durable correctness before adding autonomous capability.
- Work vertically from a tested boundary to its recovery and evidence gates.
- Treat missing infrastructure as a blocker, never as a fabricated pass.
- Keep changes scoped and update `.pi/state.md` only with observed outcomes.

## Legend

**Status:**

- `Not Started` - No work begun
- `In Progress` - Active development
- `Complete` - All tasks closed

**Type:**

- `task` - Tactical, single-session work
- `feature` - New capability, multi-session
- `epic` - Cross-domain, significant scope
- `bug` - Fix for broken behavior

## Evidence

The roadmap is grounded in `DESIGN.md`, `docs/01-domain-state-and-closure.md` through `docs/09-decision-record.md`, the current source tree, `mix deps`, and the verified local gates recorded in `.pi/state.md` and `.pi/tech-stack.md`.

---

_Update this file when phases complete or roadmap changes._
_Use `pi-fabric` plan extensions to create detailed plans for active phases._

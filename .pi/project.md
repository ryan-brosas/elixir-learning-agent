# Project

This is the verified deep-init record for the standalone Elixir Learning Agent. It describes the implementation that exists in the checkout and marks planned or unavailable capabilities explicitly.

## Purpose and Status

- **Goal** — Study one pinned source repository at a time and turn source-confirmed reusable behavior into durable, validated learning artifacts without mutating the source repository.
- **Status** — Implementation: deterministic runtime foundation complete; autonomous-learning product and container end-to-end acceptance remain partial.
- **Milestone** — The repository has implemented durable domain state, SQL persistence, scheduling/recovery, Codebase Memory MCP framing, source/tool policy, note-first records, artifact validation/activation, an adapter-first bounded agent loop, an OpenViking outbox seam, and a Plug operator API. Evidence: `docs/06-implementation-roadmap.md` milestone status sections; current verification is `112 passed` from `mix test`.
- **Next Milestone** — Complete the remaining deployment and product surfaces: live OpenViking transport, provider families/model routing, exhaustive multi-pass closure, container readiness proof, and the planned LiveView control plane. Evidence: `docs/06-implementation-roadmap.md` milestones 10, 11, 12, 13, and 15.

## Success Criteria

1. **Deterministic safety core** — The test suite proves durable transitions, lease fencing, cancellation, note-first ordering, artifact parity, tool denial, MCP framing, and outbox retry behavior. Verified by `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix test`.
2. **Runnable service boundary** — A production release assembles, the Compose topology validates, and the production image builds. Verified by `MIX_ENV=prod mix release --overwrite`, `docker compose config --quiet`, and `docker build --pull --tag learning-agent:ci .`; full Compose startup/readiness remains pending.
3. **Honest learning closure** — A future complete run can only close from persisted evidence, coverage, adjudications, artifact parity, and retrieval verification; unknown, partial, stale, or blocked work remains non-complete. Evidence: `docs/01-domain-state-and-closure.md`, `docs/05-testing-and-verification.md`, and the domain tests.

## Target Users

- **Primary:** Operators and maintainers who need repeatable, recoverable repository-learning passes and inspectable evidence.
- **Secondary:** Agents and IDE workflows that consume canonical skills and need a durable context-production backend.
- **Non-goals:** Generic coding-agent execution, arbitrary shell automation, source mutation, dependency installation into studied repositories, and a vector database as primary workflow state. Evidence: `DESIGN.md` sections 3, 5, and 15.

## Core Principles

1. **Code and direct tests are authoritative** — Graphs and retrieval select where to look; source and tests decide what can be claimed. Evidence: `DESIGN.md` document control and `README.md`.
2. **Durability before autonomy** — Intent is persisted before external side effects; note publication precedes artifact production; retries are classified. Evidence: `docs/03-storage-artifacts-and-openviking.md`, `lib/learning_agent/notes.ex`, and `lib/learning_agent/outbox_context.ex`.
3. **Fail closed on uncertainty** — Missing coverage, unsafe tools, stale pins, budget exhaustion, and unresolved work block completion rather than becoming optimistic passes. Evidence: `docs/01-domain-state-and-closure.md`, `lib/learning_agent/tool_policy.ex`, and `lib/learning_agent/recovery.ex`.

## System Context

- **External actors:** An operator, CI, a bounded learning model, and optional IDE/MCP clients.
- **External systems:** PostgreSQL; a model provider through `LearningAgent.Provider`; Codebase Memory through the runtime MCP client; OpenViking through the outbox client behavior; GitHub Actions/Qodana/JetBrains inspections for repository quality.
- **Trust boundaries:** Bearer-token role checks protect `/v1/*`; health routes are intentionally public; repository source is treated as read-only untrusted data; model/MCP/provider payloads are untrusted; database constraints and filesystem mount modes are safety boundaries.
- **Runtime and environment:** Elixir `1.20.x`, an OTP-compatible BEAM, PostgreSQL 16, Docker Compose, and a private GitHub repository with `main` as the default branch. Codebase Memory project `learning-agent` is ready with 1418 nodes and 2109 edges; `Dockerfile:31` is parse-partial and must be checked locally. Evidence: `mix.exs:4-43`, `docker-compose.yml:1-56`, `gh repo view` output, the Codebase Memory `index_status` response, and local probes (`Elixir 1.20.3`, OTP 29, Docker 29.7.2, Compose 5.5.0).

## Architecture Overview

- **Architectural style:** Modular OTP monolith with Ecto-backed durable state, supervised workers, bounded adapters, and filesystem artifact generations.
- **Component responsibilities:**
  - `LearningAgent.Application` — composition root, supervision tree, recovery startup — `lib/learning_agent/application.ex:12-47`.
  - Ecto repo and contexts — persistence, transitions, leases, notes, and outbox — `lib/learning_agent/repo.ex`, `lib/learning_agent/*_context.ex`, `priv/repo/migrations/`.
  - Scheduler/run workers — admission, one-pass execution, lease renewal, cancellation, recovery — `lib/learning_agent/scheduler.ex`, `run_supervisor.ex`, `run_worker.ex`, `lease_renewer.ex`, `recovery.ex`.
  - MCP/source/policy plane — Codebase Memory protocol, bounded source reads, registered tool firewall — `lib/learning_agent/mcp/`, `source_reader.ex`, `tool_registry.ex`, `tool_policy.ex`.
  - Learning/artifact plane — note validation/publication, capsule rendering, generations, journals, parity — `learning_note.ex`, `notes/`, `skills/`, `artifacts/`.
  - Provider/outbox plane — provider behavior and OpenAI-compatible adapter, publication intents, retry/drain — `provider.ex`, `providers/openai_compatible.ex`, `outbox.ex`, `outbox_context.ex`, `open_viking/`.
  - Operator boundary — Plug JSON health and role-gated routes — `lib/learning_agent_web/router.ex:13-104`.
- **Composition roots:** `LearningAgent.Application.start/2`, Mix release declaration in `mix.exs:16-31`, `bin/server`, and Compose services in `docker-compose.yml`.
- **Dependency rules:** Web calls contexts; contexts own durable decisions; adapters implement behaviors; model/provider/MCP/OpenViking adapters do not decide closure; workers do not execute arbitrary SQL; no source-writing or generic-shell tool exists. Evidence: `DESIGN.md` sections 17-18 and the policy/adapter modules.
- **Key data structures or schemas:** repository/pin, run/transition, lease, learning note, inventory/claim/evidence, artifact set, and outbox event records, with migrations under `priv/repo/migrations/`.

## Runtime Entrypoints

| Entrypoint | Kind | Path | Purpose | Config source |
|---|---|---|---|---|
| OTP application | service | `lib/learning_agent/application.ex` | Start supervision, recover, and conditionally serve HTTP | `config/config.exs`, `config/runtime.exs` |
| Release entrypoint | container | `bin/server` | Wait for DB, run migrations, start release foreground | `LA_DB_*`, `LA_HTTP_PORT`, `PORT` |
| Operator API | HTTP server | `lib/learning_agent_web/router.ex` | Health and authenticated JSON operations | application env + bearer-token config |
| Learning worker | supervised job | `lib/learning_agent/run_worker.ex` | Advance one durable pass and release its lease | Ecto state and run config |
| Host quality/IDE tooling | optional operator tools | `.github/workflows/`, `.idea/`, `inspections/` | CI, Qodana, and JetBrains inspection/review | GitHub secrets and IDE/MCP registration |

## Request, Data, and Event Flows

- **Primary request flow:** HTTP request → Plug router → authentication/authorization → Ecto context → JSON response. Health routes are public; `/v1/*` is role-gated. Evidence: `lib/learning_agent_web/router.ex:13-80`.
- **Run flow:** repository/run admission → scheduler claim → lease epoch → temporary run worker → durable transitions → lease release; recovery requeues or terminally resolves orphaned work. Evidence: `lib/learning_agent/scheduler.ex`, `run_context.ex`, `run_worker.ex`, `recovery.ex`.
- **Learning flow:** graph/MCP preflight → bounded source/tool calls → note draft/materialization/read-back hash → capsule/artifact validation → generation activation → outbox intent → remote publication/verification. Evidence: `docs/02-...`, `docs/03-...`, `lib/learning_agent/notes.ex`, `artifacts/publisher.ex`, `open_viking/publisher.ex`.
- **Write and read paths:** Ecto contexts write SQL records; note and artifact publishers write staged filesystem generations; outbox records external intents; publishers read claims and mark delivery/retry/permanent failure.
- **Background processing:** OTP scheduler and lease-renewer loops; DynamicSupervisor run children; startup recovery. Test configuration disables scheduler/renewer automatically to protect the Ecto Sandbox.
- **Failure behavior:** invalid transitions and policy denials are returned as decisions; lease conflicts are fenced; transient provider/publication errors enter bounded retry states; permanent/unsupported events fail permanently; uncertain external results are recorded for reconciliation. Evidence: context tests and `docs/03`.

## Configuration

- **Configuration sources:** compile-time project config in `config/config.exs`; release-time environment resolution in `config/runtime.exs`; Compose supplies service-network values. Environment values override the local defaults.
- **Secrets:** database credentials, bearer tokens, provider credentials, and MCP credentials must come from environment/secret storage. No secret belongs in tracked Markdown, Qodana, workflow, or source files.
- **Environments:** test uses Ecto SQL Sandbox and disables background loops; local development defaults to host PostgreSQL port 5433; production release uses `LA_DB_*` and HTTP port 4000; Compose uses PostgreSQL service DNS and internal port 5432.
- **Validation:** malformed path/tool/gate inputs are rejected by `SourceReader`/`ToolPolicy`; invalid domain transitions are rejected before durable mutation; readiness probes `SELECT 1`; release startup waits for the database and runs migrations.

## Data Ownership

- **Stores and schemas:** PostgreSQL is owned by `LearningAgent.Repo`; migration history is in `priv/repo/migrations/`; filesystem state is split into note files, staged/active artifact generations, journal/manifest records, and Compose volumes.
- **Cache ownership:** No business cache is authoritative; `.pi/fabric`, `_build`, `deps`, and `cover` are generated/local state and excluded from product evidence.
- **Transaction boundaries:** Ecto contexts own transition/lease/outbox transactions; filesystem publication uses staging, journal, swap, verification, and commit markers; remote delivery follows persisted outbox intent.
- **Migration mechanism:** `mix ecto.migrate` locally/CI; `bin/server` runs all release migrations before starting the service.

## External Integrations

| Service | Auth | Docs | Rate limits | Error handling |
|---|---|---|---|---|
| PostgreSQL 16 | `LA_DB_USER`/`LA_DB_PASS` | `config/config.exs`, `config/runtime.exs` | connection pool | readiness check, Ecto errors, Compose healthcheck |
| Codebase Memory MCP | deployment/transport configuration | `lib/learning_agent/mcp/` and `docs/02` | bounded per-run calls | framed correlation, timeout/disconnect classification, pin/coverage checks |
| Model provider | provider-specific environment/registry | `lib/learning_agent/provider.ex` | run budgets and adapter policy | normalized provider errors, bounded timeout retry |
| OpenViking | configured client transport | `lib/learning_agent/open_viking/` and `docs/03` | outbox retry budget | local success independent of remote availability; retry/permanent state |
| GitHub Actions/Qodana/JetBrains | GitHub permissions, optional `QODANA_TOKEN`, IDE session | `.github/workflows/`, `qodana.yaml`, `.idea/mcp-steroid.md` | CI/vendor-specific | workflow status and inspection artifacts are supplementary evidence |

## Deployment Topology

- **Build artifacts:** Multi-stage Docker image containing a production OTP release; local release output is `_build/prod/rel/learning_agent` and is ignored.
- **Runtime services:** Compose `postgres` plus all-in-one `app`; optional `worker` replicas under the `scale-out` profile. The default application exposes port 4000.
- **Environments:** local Mix + host PostgreSQL, CI service PostgreSQL + Beam setup, and Compose/release deployment. Promotion is not automated yet.
- **Health checks:** HTTP `/health/live` and `/health/ready`; PostgreSQL Compose healthcheck `pg_isready`; the app entrypoint waits on SQL before migrations.
- **Rollback path:** Artifact generations retain `.bak` activation state and journals; database rollback/backup and full forced-restart recovery are not yet a verified deployment procedure. Marked open in `docs/06` milestone 15.

## Testing Architecture

- **Unit/integration seams:** ExUnit domain and context tests; Ecto tests against PostgreSQL; MCP protocol/client tests over a real TCP stub; source/policy traversal tests; note/artifact/outbox/router tests.
- **Test locations:** `test/` and `test/support/`; test compilation includes `test/support` through `mix.exs:33-34`.
- **Live boundary probes:** local PostgreSQL and socket MCP stubs are exercised; live external model/OpenViking transport and full Compose readiness are not part of the current local green gate.
- **Coverage gaps:** no configured coverage threshold; full fault-injection sweep, LiveView/browser tests, additional provider adapters, and production external transport tests remain open. Evidence: `docs/05` and `docs/06`.

## Observability

- **Logging:** Plug request logging and Elixir Logger; current logs include Ecto/Plug runtime events.
- **Metrics:** `LearningAgent.Telemetry` defines event names and a Prometheus-style formatter exposed by the telemetry context; high-cardinality source symbols are not labels.
- **Tracing:** distributed tracing is designed but not emitted at every boundary; this is an explicit remaining M14 item.
- **Alerting:** GitHub workflow failures and health/readiness failures are the available operational signals; no pager integration is configured.

## Failure Modes

| Failure | Symptom | Detection | Recovery |
|---|---|---|---|
| Database unavailable | readiness 503 or entrypoint waits | `/health/ready`, SQL probe, Compose healthcheck | restore DB/network; entrypoint retries before migration |
| Worker/lease loss | queued or orphaned run | recovery scan and lease expiry | requeue or terminally resolve cancelled orphan |
| Stale worker | fenced transition rejected | lease epoch check | discard stale result and let durable recovery decide |
| Note publication crash | draft without published file/status | note recovery/hash check | reconcile file, promote matching content, or mark conflict |
| Artifact swap interruption | stage/journal mismatch | manifest/journal verification | recover staged/active generation and preserve backup |
| External publication outage | outbox retry/permanent state | publisher outcome and telemetry | retry within budget or operator retry endpoint |
| Unsafe model/tool request | policy denial | registered gate/policy decision | stop the loop; do not broaden capabilities automatically |

## Architectural Invariants

- No external side effect precedes a durable intent and idempotency key.
- No artifact is activated before note-first ordering, validation, and manifest verification.
- No stale lease holder may commit a transition.
- No source repository mutation, dependency installation, arbitrary shell, or delegated learning judgment is available through the runtime tool plane.
- OpenViking degradation must be visible and must not erase locally complete learning.
- Completion claims are bounded by declared pin, scope, coverage, evidence, and direct verification; model confidence alone never closes work.

## Decisions

| Date | Decision | Rationale | Alternatives | Record |
|---|---|---|---|---|
| 2026-08-29 | PostgreSQL-first durable state | leases, constraints, and outbox need transactional SQL | SQLite appliance profile | `docs/09-decision-record.md`, `DESIGN.md` |
| 2026-08-29 | MCP boundaries for Codebase Memory/OpenViking | preserves typed, replaceable external integrations | deployment-specific native/sidecar transport | `docs/09-decision-record.md`, `lib/learning_agent/mcp/`, `lib/learning_agent/open_viking/` |
| 2026-08-29 | Adapter-first model plane | keeps provider-neutral loop and keyless tests | provider-specific loop, multi-agent delegation | `docs/09-decision-record.md`, `lib/learning_agent/provider.ex` |
| 2026-08-29 | Plug JSON API before planned LiveView | current operator surface is small and testable | immediate frontend implementation | `lib/learning_agent_web/router.ex`, `docs/07-frontend-control-plane.md` |

## Known Risks and Hotspots

- Full Compose startup/readiness and Qodana are not locally verified; the OTP29.0.5 production image build is locally verified and remains covered by CI.
- The source design is broader than the current runtime: LiveView, multi-provider routing, exhaustive closure, and external transport wiring remain significant work.
- Artifact activation is documented as atomic-ish with recovery tradeoffs; full fault-injection coverage is incomplete.
- Authentication is bearer-token role gating, but deployment identity/reverse-proxy integration is still open.
- `qodana.yaml` and IDE inspection exports are quality inputs, not replacements for executable Elixir tests.

## Open Questions

| Question | Context | Blocking | Priority |
|---|---|---|---|
| Which production Codebase Memory/OpenViking transport and credentials are deployed? | runtime adapter seams exist; endpoint provisioning is not in this checkout | yes for live external integration | high |
| What are the default provider models, credentials, cost, and wall-time budgets? | autonomous turns must remain bounded | yes for production model use | high |
| When should the planned LiveView frontend land? | Plug API exists; UI docs are design-required | no for deterministic core | medium |
| What backup/restore and image-scanning policy is required? | container hardening milestone is partial | yes for production definition of done | medium |
| What license should be selected? | private GitHub repository has no license metadata | no for local development; yes for redistribution | medium |

## Evidence

Primary evidence used for this record: Codebase Memory project `learning-agent` (`index_status`: ready, 1418 nodes, 2109 edges; parse-partial `Dockerfile:31`); `mix.exs:4-43`; `config/config.exs`; `config/runtime.exs:3-11`; `lib/learning_agent/application.ex:12-47`; `lib/learning_agent_web/router.ex:13-104`; `docker-compose.yml:1-56`; `Dockerfile:1-31`; `bin/server:1-15`; `qodana.yaml:10-55`; `docs/01-09`; `DESIGN.md`; `mix deps`; `mix format --check-formatted`; `mix compile --warnings-as-errors`; `mix test` (112 passed); `MIX_ENV=prod mix release --overwrite`; `docker compose config --quiet`; authenticated `gh repo view` output; JetBrains MCP Steroid project/window listing.

---

_Update this file when architecture or project direction changes._
_AI reads this on demand to stay aligned with project goals and invariants._

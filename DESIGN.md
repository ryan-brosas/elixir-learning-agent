# Standalone Elixir Repository-Learning Agent — Design

## Document control

- Project: Elixir Learning Agent.
- Document type: implementation-ready architecture plan.
- Status: implemented foundation with planned follow-on surfaces.
- Runtime implementation: event-sourced foundation projection is implemented; see `docs/10-event-sourced-foundations.md`.
- Product category: autonomous evidence-backed repository learner.
- Primary language: Elixir.
- Runtime model: OTP application.
- Deployment model: containerized service.
- Primary truth: source code and direct tests.
- Navigation surface: Codebase Memory MCP.
- Reusable output: `.agents/skills/<slug>-foundation/`.
- Semantic publication: OpenViking.
- Explicit non-category: retrieval-augmented generation application.

## 1. Problem

Existing repository-learning work is driven by host schedulers such as cron or DSH Factory.

Those hosts are useful triggers but do not constitute a standalone product.

The desired product must own the entire lifecycle.

It must know which repository to study.

It must know what has already been learned.

It must know what remains unresolved.

It must supervise model turns.

It must constrain tool calls.

It must preserve evidence.

It must recover from crashes.

It must publish canonical foundation projections.

It must synchronize learning into OpenViking.

It must never confuse graph presence with behavioral proof.

It must never claim completeness because a capsule count was reached.

It must run without Hermes or DSH.

## 2. Goals

### G-001 Standalone operation

The application starts from its own release entrypoint.

The application exposes its own operator API.

The application schedules its own repository passes.

The application stores its own durable state.

### G-002 Evidence-backed learning

Every reusable claim has a source anchor.

Every reusable claim records graph discovery evidence.

Every reusable claim records index coverage evidence.

Every reusable claim records a direct test or test caveat.

Every reusable claim records a deterministic probe.

### G-003 Durable foundation projection

Every pass records an immutable, pin-scoped observation and writes a note-first work record.

Every accepted capsule follows capsule-v2 and binds direct source evidence.

Every pass projects the complete current-pin capsule set into the canonical `<slug>-foundation` loader and map shape.

Every publication is recoverable after process or host failure. Automatic execution never emits or activates procedures.

### G-004 Honest closure

Completion is computed from persisted adjudications.

Unknown work prevents completion.

Partial work prevents completion.

Stale work prevents completion.

Unresolved coverage gaps prevent completion.

Reasoned non-reusable omissions do not prevent completion.

### G-005 Safe autonomy

The model sees only registered tools.

The model cannot install dependencies.

The model cannot write target source.

The model cannot launch helper scripts.

The model cannot delegate repository learning.

The model cannot exceed turn, token, time, or cost budgets.

### G-006 Operational transparency

Every run has a correlation identifier.

Every state transition is recorded.

Every external call emits metrics.

Every terminal state includes evidence or a blocker.

## 3. Non-goals

### NG-001 Generic coding agent

The product does not implement arbitrary coding tasks.

### NG-002 Source mutation

The product never edits the repository it studies.

### NG-003 Build service

The product does not install packages or compile arbitrary repositories.

### NG-004 General RAG service

The product does not answer arbitrary questions over embeddings.

### NG-005 Human-equivalent comprehension claim

The product does not certify subjective understanding of every line.

### NG-006 Multi-agent delegation

The learning model does not hand source judgment to subordinate models.

### NG-007 Immediate distributed architecture

The first release does not require microservices or a message broker.

## 4. Inherited constraints

The following constraints are verified from the existing mining workflow.

### IC-001 One repository per lane

A run may study exactly one source repository.

### IC-002 Graph preflight

The run begins with project enumeration and index status.

### IC-003 Pin identity

Graph root, branch, and HEAD must match the admitted repository pin.

### IC-004 Graph-led discovery

Architecture and graph relationships select a connected seam.

### IC-005 Direct confirmation

Exact source and direct tests decide behavioral claims.

### IC-006 Coverage checks

Every cited file receives an exact coverage check.

### IC-007 Note first

The learning note exists before capsule or skill production.

### IC-008 Production batch

A normal pass targets five to eight durable outcomes.

### IC-009 Honest fewer-than-five result

Closure or blockers may justify fewer outcomes.

### IC-010 Canonical output

The foundation skill and capsule-v2 templates define output shape.

### IC-011 Pressure testing

The product tests retrieval and behavioral guidance, including an adversarial query.

### IC-012 OpenViking degradation

OpenViking failure is recorded but does not invalidate locally complete production.

### IC-013 Durable resume state

The next pass starts from persisted concrete targets.

### IC-014 No shortcuts

No generated scripts, broad scans, or delegated source learning are accepted.

## 5. Options considered

### Option A: Filesystem event log and embedded state only

#### Description

Store repository records, run events, notes, and manifests as append-only files.

Use a single OTP process to serialize writes.

Use SQLite only for optional indexing.

#### Advantages

Small deployment footprint.

Easy export and inspection.

No separate database service.

Natural alignment with Markdown work records.

#### Disadvantages

Cross-file invariants require custom recovery code.

Lease claims are difficult across replicas.

Transactional outbox semantics become manual.

Querying closure matrices becomes expensive.

Schema evolution is fragile.

Concurrent operator requests are harder to serialize safely.

#### Verdict

Do not choose as the primary state architecture.

Keep append-only event export as an audit feature.

### Option B: SQL-backed modular OTP monolith

#### Description

Run one Elixir release.

Persist normalized workflow state in SQL.

Use OTP processes for admission, supervision, workers, and publishers.

Use filesystem volumes only for repositories, staging, and skill artifacts.

#### Advantages

Clear transaction boundaries.

Durable unique constraints.

Reproducible closure queries.

Crash-safe outbox.

Lease-safe future replication.

Simple first deployment.

No broker required.

#### Disadvantages

Requires database schema and migrations.

File publication still needs a recovery journal.

Database choice affects deployment complexity.

#### Verdict

Chosen architecture.

### Option C: Distributed services and queue

#### Description

Separate scheduler, agent workers, artifact service, and publication service.

Use a broker and distributed leases.

#### Advantages

Independent scaling.

Failure isolation across services.

Natural multi-tenant boundaries.

#### Disadvantages

Too many distributed transactions.

Harder note-first ordering.

More operational dependencies.

Premature for one-repository-per-pass work.

Harder local deployment.

#### Verdict

Reject for initial product.

Extract services only after measured bottlenecks.

## 6. Chosen architectural style

Use a modular monolith.

Use domain modules with explicit behaviors at external boundaries.

Use OTP supervision for liveness.

Use SQL for durable decisions.

Use filesystem generations for skill artifacts.

Use an outbox for OpenViking publication.

Use a bounded model-driven state machine for learning.

Do not store business truth only in a process mailbox.

Do not infer durable state from logs.

Do not allow external side effects before the corresponding durable intent exists.

## 7. Proposed top-level modules

### `LearningAgent.Application`

Owns the supervision tree.

Validates startup configuration.

Starts no worker before migrations and readiness succeed.

### `LearningAgent.Config`

Loads runtime configuration.

Redacts secrets.

Rejects inconsistent path or transport settings.

### `LearningAgent.Repo`

Owns SQL persistence.

Exposes transaction helpers.

Does not expose raw connection state to domain code.

### `LearningAgent.Repositories`

Registers source repositories.

Pins source identity.

Tracks active and completed generations.

### `LearningAgent.Runs`

Creates runs.

Transitions durable run state.

Records cancellation intent.

### `LearningAgent.Scheduler`

Admits queued runs.

Enforces global concurrency.

Enforces one active run per repository.

### `LearningAgent.Leases`

Claims repository work.

Renews leases.

Reclaims expired leases.

Releases terminal leases.

### `LearningAgent.RunSupervisor`

A `DynamicSupervisor` for pass workers.

Uses temporary children because durable state drives restart.

### `LearningAgent.RunWorker`

Owns one active pass process.

Interprets the durable run state machine.

Persists before side effects.

### `LearningAgent.AgentLoop`

Builds model requests.

Validates tool calls.

Executes one tool call at a time.

Enforces budgets.

### `LearningAgent.ToolPolicy`

Defines the allowlist.

Validates arguments.

Rejects path escapes.

Rejects write-capable source operations.

### `LearningAgent.Provider.Registry`

Owns provider and model profile projections.

### `LearningAgent.ModelRouter`

Selects an eligible model profile from a pinned route revision.

### `LearningAgent.CapacityManager`

Reconciles global, instance, provider, and model concurrency settings.

### `LearningAgent.Provider.Supervisor`

Supervises provider pools and health processes.

### `LearningAgent.MCP.CodebaseMemory`

Implements Codebase Memory operations.

Normalizes MCP responses.

Records request and response hashes.

### `LearningAgent.SourceReader`

Reads bounded source ranges.

Confirms repository-relative containment.

Computes content hashes.

### `LearningAgent.ProbeRunner`

Runs only registered probes.

Has no arbitrary shell interface.

May be disabled.

### `LearningAgent.Inventory`

Builds subsystem and seam inventories.

Tracks adjudication state.

Computes closure inputs.

### `LearningAgent.Evidence`

Creates immutable evidence records.

Separates navigational from authoritative evidence.

### `LearningAgent.Notes`

Creates and publishes learning notes.

Produces canonical Markdown work records.

### `LearningAgent.Skills.Synthesizer`

Constructs proposed leaf and capsule content.

Cannot publish directly.

### `LearningAgent.Skills.Validator`

Validates capsule-v2 sections.

Validates source anchors.

Validates loader, map, and disk parity.

### `LearningAgent.Artifacts.Publisher`

Stages generations.

Writes a recovery journal.

Activates verified generations.

### `LearningAgent.OpenViking.Outbox`

Creates idempotent publication events.

### `LearningAgent.OpenViking.Publisher`

Retries OpenViking delivery.

Verifies one newly cited symbol after publication.

### `LearningAgent.Recovery`

Reconciles interrupted runs.

Repairs interrupted filesystem publications.

Requeues eligible durable work.

### `LearningAgent.Telemetry`

Declares metric and trace events.

### `LearningAgentWeb.Router`

Exposes operator and health endpoints.

Does not expose unrestricted tool execution.

### `LearningAgentWeb.Live`

Provides the required Phoenix LiveView operations frontend.

Subscribes to PubSub change notifications and reloads durable SQL projections.

### `LearningAgent.Instances`

Tracks application roles, worker slots, heartbeats, and drain state.

## 8. Proposed supervision tree

```text
LearningAgent.Supervisor
├── LearningAgent.Repo
├── LearningAgent.Telemetry
├── LearningAgent.MCP.Supervisor
│   └── LearningAgent.MCP.CodebaseMemory.ConnectionPool
├── LearningAgent.Provider.Supervisor
│   ├── LearningAgent.Provider.Registry
│   ├── LearningAgent.ModelRouter
│   ├── LearningAgent.CapacityManager
│   └── provider HTTP pools
├── LearningAgent.LeaseRenewer
├── LearningAgent.Recovery
├── LearningAgent.RunSupervisor
├── LearningAgent.Scheduler
├── LearningAgent.OpenViking.Supervisor
│   └── LearningAgent.OpenViking.Publisher
└── LearningAgentWeb.Endpoint
```

### Supervision decisions

Use `:one_for_one` at the root.

A failed MCP connection must not restart the database.

A failed publisher must not restart active learning runs.

A failed run worker must not restart sibling runs.

A run worker is not blindly restarted from in-memory arguments.

Recovery reads durable state and decides whether to resume or requeue.

Lease renewal is independent of model calls.

Provider connection pools are independent of run workers.

## 9. Composition root

`LearningAgent.Application.start/2` performs:

1. Load validated runtime configuration.
2. Start the SQL repository.
3. Verify schema migration level.
4. Verify required mounted paths.
5. Verify source root is read-only when enforcement is enabled.
6. Start MCP and provider supervisors.
7. Start recovery reconciliation.
8. Start run supervision.
9. Start scheduler admission.
10. Start publisher and operator API.

The scheduler remains paused until recovery finishes.

## 10. External boundaries

### Model provider boundary

```elixir
@callback complete(ModelRequest.t()) ::
  {:ok, ModelResponse.t()} |
  {:error, ProviderError.t()}
```

### Codebase Memory boundary

```elixir
@callback call(operation(), map(), RequestContext.t()) ::
  {:ok, MCPResult.t()} |
  {:error, MCPError.t()}
```

### Source reader boundary

```elixir
@callback read_range(repo_id(), relative_path(), line_range()) ::
  {:ok, SourceExcerpt.t()} |
  {:error, SourceReadError.t()}
```

### Probe boundary

```elixir
@callback run(probe_spec(), ProbeContext.t()) ::
  {:ok, ProbeResult.t()} |
  {:error, ProbeError.t()}
```

### Artifact publisher boundary

```elixir
@callback publish(artifact_set_id()) ::
  {:ok, PublishedGeneration.t()} |
  {:error, PublicationError.t()}
```

### OpenViking boundary

```elixir
@callback add(resource_spec(), idempotency_key()) ::
  {:ok, remote_ref()} |
  {:error, OpenVikingError.t()}
```

```elixir
@callback find(query(), target_uri()) ::
  {:ok, [SearchHit.t()]} |
  {:error, OpenVikingError.t()}
```

## 11. Primary lifecycle

1. Operator registers a repository.
2. System verifies canonical source identity.
3. Operator or policy queues a learning run.
4. Scheduler claims a repository lease.
5. Worker verifies the Codebase Memory project.
6. Worker records index identity and caveats.
7. Worker loads bounded current-pin context: accepted seams, coverage, unresolved items, and omissions.
8. Worker studies one connected subsystem and records an immutable pass observation with direct evidence.
9. Worker accepts zero or more stable seam capsules; conflicting content at an existing seam identity fails closed.
10. Worker creates and publishes a durable learning-note work record for causal ordering.
11. Worker renders the complete current-pin `<slug>-foundation` projection, including every valid prior capsule.
12. Validator checks foundation-only frontmatter, evidence, loader/map/disk parity, ownership, and manifest identity.
13. Publisher stages, journals, and atomically activates the content-addressed projection, or reports it unchanged.
14. SQL records the active projection and OpenViking outbox entries.
15. OpenViking publisher sends the work record, accepted capsules, and materialized foundation.
16. Worker updates closure state, releases the lease, and records terminal state.

## 12. Durability rule

Every externally visible side effect has a durable intent.

Every durable intent has an idempotency key.

Every side effect records an observed result.

An uncertain result is reconciled before retry.

## 13. Observation and note-first rule

A pass observation is an immutable pin-scoped fact. Accepted capsules reference one observation and use stable seam identities independent of pass number.

A production projection retains a compatibility link to exactly one committed learning-note work record. The note proves causal ordering and supports crash recovery; it is not cumulative memory and later-pass context never includes its full body.

The state machine still rejects synthesis before `note_published`. Projection activation then derives only from accepted capsules at the active pin, and recovery verifies the content-addressed generation before resuming publication.

This establishes causal ordering without relying on timestamps and keeps durable facts separate from their rebuildable filesystem projection.

## 14. Repository pass budget

Every run has configured limits:

- Maximum model turns.
- Maximum MCP calls.
- Maximum source reads.
- Maximum probe executions.
- Maximum input tokens.
- Maximum output tokens.
- Maximum estimated provider cost.
- Maximum wall-clock duration.
- Maximum consecutive policy violations.
- Maximum transient retries per boundary.

Budget exhaustion produces `blocked_budget`.

Budget exhaustion never produces `complete`.

## 15. Trust model

The model is untrusted control input.

MCP responses are untrusted external input.

Repository content is untrusted data.

Generated Markdown is untrusted until validated.

OpenViking is an external side effect.

Operators are authenticated principals.

Database constraints are part of the safety boundary.

Filesystem mount flags are part of the safety boundary.

## 16. Design decisions

### DD-001 Modular monolith

Status: proposed and recommended.

Reason: minimizes distributed transaction count.

### DD-002 SQL durable state

Status: proposed and recommended.

Reason: closure and idempotency require queryable constraints.

### DD-003 PostgreSQL baseline

Status: decision required.

Reason: strongest lease and outbox semantics.

Alternative: SQLite for single-node appliance profile.

### DD-004 Direct owned tool loop

Status: proposed and recommended.

Reason: policy enforcement is the product core.

Alternative: general Elixir agent framework.

### DD-005 MCP transport abstraction

Status: required.

Initial transport: decision required.

### DD-006 Versioned artifact generations

Status: proposed and recommended.

Activation mechanism: decision required.

### DD-007 OpenViking outbox

Status: proposed and recommended.

Transport details: decision required.

### DD-008 No arbitrary shell

Status: proposed for milestone one.

Reason: preserves no-install and no-script constraints.

### DD-009 Phoenix operations frontend

Status: required.

Phoenix LiveView is the version-one frontend.

It shares domain contexts with the JSON API and receives real-time hints through PubSub.

### DD-010 One model learns each seam

Status: inherited.

Reason: no delegated repository judgment.

### DD-011 Multi-provider model plane

Status: required.

The complete release supports OpenAI-compatible, Anthropic, Gemini, and Ollama/local adapter families with multiple configurable model profiles.

Model identifiers, capabilities, costs, routes, and limits are runtime configuration rather than source constants.

### DD-012 Runtime-adjustable capacity

Status: required.

Global, per-instance, per-provider, and per-model limits are typed versioned settings.

Increasing capacity admits more work immediately; decreasing capacity drains active work by default.

### DD-013 Runnable Docker product

Status: required.

The default Compose profile runs Phoenix web, scheduler, workers, publisher, and PostgreSQL.

The scale-out profile reuses one release image with role-specific services and scalable worker replicas.

Implementation acceptance requires `docker compose up --build -d` and a ready frontend on port 4000.

## 17. Implementation layout

```text
lib/
├── learning_agent.ex
├── learning_agent/application.ex
├── learning_agent/config.ex
├── learning_agent/repo.ex
├── learning_agent/repositories.ex
├── learning_agent/runs.ex
├── learning_agent/scheduler.ex
├── learning_agent/leases.ex
├── learning_agent/recovery.ex
├── learning_agent/run_supervisor.ex
├── learning_agent/run_worker.ex
├── learning_agent/agent_loop.ex
├── learning_agent/tool_policy.ex
├── learning_agent/inventory.ex
├── learning_agent/evidence.ex
├── learning_agent/notes.ex
├── learning_agent/mcp/client.ex
├── learning_agent/mcp/codebase_memory.ex
├── learning_agent/provider/behaviour.ex
├── learning_agent/provider/registry.ex
├── learning_agent/provider/openai_compatible.ex
├── learning_agent/provider/anthropic.ex
├── learning_agent/provider/gemini.ex
├── learning_agent/provider/ollama.ex
├── learning_agent/model_router.ex
├── learning_agent/capacity_manager.ex
├── learning_agent/source_reader.ex
├── learning_agent/probe_runner.ex
├── learning_agent/skills/synthesizer.ex
├── learning_agent/skills/validator.ex
├── learning_agent/artifacts/publisher.ex
├── learning_agent/open_viking/client.ex
├── learning_agent/open_viking/outbox.ex
├── learning_agent/open_viking/publisher.ex
└── learning_agent_web/router.ex
```

## 18. Dependency direction

Web depends on application services.

Application services depend on domain modules.

Domain modules depend on behaviors and value types.

Adapters implement behaviors.

Adapters may depend on HTTP, SQL, JSON, or filesystem libraries.

Domain modules never call HTTP clients directly.

Domain modules never parse provider-specific response shapes.

Run workers never execute raw SQL.

Model providers never publish artifacts.

MCP adapters never decide closure.

OpenViking adapters never schedule work.

## 19. Readiness definition

The service is live when the BEAM is running.

The service is ready only when:

- Configuration is valid.
- Database is reachable.
- Schema is current.
- State volume is writable.
- Source volume is readable.
- Skill volume is writable.
- Recovery reconciliation completed.
- Required model provider credentials exist.
- Required MCP transport is configured.

OpenViking may be degraded without making the core service unready.

The degraded state must be visible.

## 20. Completion claim boundary

The service may claim:

- A graph project was verified.
- A path was checked for coverage.
- A source excerpt was read.
- A direct test was read.
- A probe produced an observed result.
- A capsule preserved a named invariant.
- A subsystem inventory has no unresolved reusable seams.

The service may not claim:

- The index contains every semantic fact.
- Every source line is understood.
- A missing graph result proves code absence.
- A missing test proves behavior.
- OpenViking retrieval proves source correctness.
- Model confidence proves closure.

## 21. Cross-document map

Domain states and closure are specified in `docs/01-domain-state-and-closure.md`.

Agent and MCP behavior are specified in `docs/02-agent-loop-and-mcp.md`.

Persistence and publication are specified in `docs/03-storage-artifacts-and-openviking.md`.

Security and operations are specified in `docs/04-security-deployment-and-observability.md`.

Verification is specified in `docs/05-testing-and-verification.md`.

Delivery phases are specified in `docs/06-implementation-roadmap.md`.

The required Phoenix LiveView control plane is specified in `docs/07-frontend-control-plane.md`.

Multi-provider routing, runtime capacity, worker replicas, and Docker role profiles are specified in `docs/08-model-routing-workers-and-scaling.md`.

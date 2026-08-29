# Security, Deployment, Configuration, and Observability

## 1. Security objectives

The product studies untrusted repositories.

The product consumes untrusted model output.

The product consumes untrusted MCP responses.

The product writes privileged reusable skills.

The product sends data to external model and memory services.

Security controls must exist outside the prompt.

## 2. Trust boundaries

### Operator boundary

Operators register repositories and credentials.

Operators can queue, cancel, pause, and resume runs.

Operators can approve configuration changes.

Operators cannot bypass evidence invariants through the model API.

### Model-provider boundary

Prompts leave the deployment.

Source excerpts may leave the deployment.

Provider responses are untrusted control input.

Provider credentials are secrets.

### MCP boundary

Codebase Memory responses are untrusted structured input.

The MCP server may be local, sidecar, or remote.

The client enforces response size and request correlation.

### Source-volume boundary

Repository files are untrusted content.

The source mount is read-only.

Repository symlinks may target outside the root.

Path containment is enforced after canonical resolution.

### Skill-volume boundary

Generated output can influence future agents.

Only validated generations become active.

The model cannot write the active catalog directly.

### OpenViking boundary

Learning artifacts leave the local deployment.

Publication is configurable per repository.

Deletion is never automatic.

## 3. Threat model

### T-001 Prompt injection in source

A source comment instructs the model to run forbidden actions.

Mitigations:

- Source is labeled as untrusted data.
- Tool policy ignores prose authorization.
- No general shell tool exists.
- State and gate permissions are deterministic.
- Policy denials are audited.

### T-002 Path traversal

A tool argument contains `../` or an absolute path.

Mitigations:

- Require repository-relative paths.
- Canonicalize joined paths.
- Check canonical prefix.
- Reject symlink escapes.
- Open read-only handles.

### T-003 Symlink swap

A source symlink changes between validation and read.

Mitigations:

- Prefer immutable source snapshots.
- Resolve and open with safe filesystem primitives.
- Verify file metadata after read.
- Recheck pin and digest.

### T-004 Tool-schema smuggling

The model places shell text inside a nominally safe argument.

Mitigations:

- Strict schemas.
- Enumerated operations.
- No command-string arguments.
- Bounded regular expressions.
- Argument normalization.

### T-005 Repository denial of service

A repository contains huge files or pathological structures.

Mitigations:

- Byte and line limits.
- MCP response limits.
- Per-run budgets.
- Deadlines.
- Memory monitoring.
- Explicit oversized-file blockers.

### T-006 Artifact prompt injection

Generated skills contain instructions beyond learned contracts.

Mitigations:

- Canonical templates.
- Required sections.
- Forbidden-content checks.
- Evidence-bound claims.
- Diff and pressure tests.

### T-007 Cross-repository contamination

Evidence from one repository enters another leaf.

Mitigations:

- Repository ID on every record.
- Context query scopes by repository and run.
- Artifact validator checks source identity.
- One repository per worker.

### T-008 Stale worker publication

An expired worker activates artifacts.

Mitigations:

- Lease epochs.
- Compare-and-set transitions.
- Epoch check before every protected write.
- Publication journal fencing.

### T-009 Credential leakage

Secrets enter prompts, logs, evidence, or artifacts.

Mitigations:

- Typed secret values.
- Redaction before serialization.
- Header allowlists.
- Secret scanner on generated artifacts.
- Logs contain credential references, never values.

### T-010 OpenViking exfiltration

Private repository content is published unintentionally.

Mitigations:

- Per-repository publication policy.
- Excerpt-size limits.
- Destination allowlist.
- Pre-publication data classification.
- Audit event per resource.

### T-011 SSRF

Configured HTTP endpoints target internal metadata services.

Mitigations:

- Endpoint allowlists.
- Scheme restrictions.
- DNS and resolved-address checks where required.
- Disable redirects by default.
- Explicit proxy policy.

### T-012 Artifact race

Readers observe an inconsistent skill generation.

Mitigations:

- Generation staging.
- Publication lock.
- Atomic pointer strategy when supported.
- Recovery journal.
- Parity verification after activation.

## 4. Authentication and authorization

### Operator API authentication

Version one should support bearer tokens or deployment-provided identity.

Production recommendation: reverse-proxy identity or signed service tokens.

The exact mechanism requires deployment confirmation.

### Roles

- `viewer`.
- `operator`.
- `administrator`.

### Viewer permissions

- Read repository status.
- Read run status.
- Read non-secret evidence metadata.
- Read metrics summaries.

### Operator permissions

- Register an allowed repository.
- Queue a run.
- Cancel a run.
- Resolve a blocker.
- Retry an OpenViking event.

### Administrator permissions

- Configure providers.
- Configure MCP endpoints.
- Change publication policy.
- Manage retention.
- Disable repositories.

The model has no operator role.

## 5. Container security

Run as a non-root user.

Use a read-only root filesystem.

Mount `/sources` read-only.

Mount `/state` read-write.

Mount `/agents/skills` read-write.

Drop Linux capabilities.

Set `no-new-privileges`.

Use a seccomp profile.

Limit processes.

Limit memory.

Limit CPU.

Limit temporary storage.

Use a dedicated writable temporary directory.

Do not mount the Docker socket.

Do not mount host SSH keys.

Do not include package managers in the runtime image when avoidable.

Do not include compilers in the runtime image.

## 6. Proposed Docker topology

```text
browser / operator
   | LiveView + HTTPS
   v
learning-agent Phoenix/OTP container
   |-- SQL connection --> postgres container
   |-- MCP connection --> codebase-memory endpoint or sidecar
   |-- HTTPS -----------> model provider
   |-- HTTPS/MCP -------> OpenViking
   |-- read-only -------> source volume
   |-- read-write ------> state volume
   `-- read-write ------> skill catalog volume
```

### App container

Contains one Phoenix-enabled Mix release.

The default role set runs web, scheduler, worker, and publisher.

The scale-out profile reuses the image with `web`, `scheduler`, `worker`, or `publisher` roles.

Contains runtime libraries only.

Exposes operator and health HTTP ports.

### Database container

Uses a persistent volume.

Is not exposed publicly.

Uses health checks.

### Codebase Memory

Deployment is unresolved.

Candidate A: remote streamable HTTP MCP.

Candidate B: trusted sidecar using stdio.

Candidate C: external service behind an MCP gateway.

The app must not install Codebase Memory at runtime.

### OpenViking

Deployment is unresolved.

The app expects an authenticated service or MCP endpoint.

The app does not assume the host `ov` CLI exists.

## 7. Image build

Use a multi-stage build.

Builder includes Elixir, Erlang, Hex, Rebar, and compiler dependencies.

Runtime includes the assembled release and required system libraries.

Pin Elixir and OTP versions.

Pin base image digest in production.

Generate an SBOM.

Scan dependencies and image layers.

Run as the release user.

## 8. Release operation

The release uses `config/runtime.exs` for environment configuration.

Migrations run as an explicit release command.

Startup does not silently run destructive migrations.

Readiness remains false until schema compatibility passes.

Graceful shutdown stops admission first.

Graceful shutdown requests workers to checkpoint.

Graceful shutdown waits for a bounded drain.

Outbox events remain durable if publisher shutdown times out.

## 9. Configuration sources

Precedence, highest first:

1. Explicit command-line boot options for emergency read-only mode.
2. Environment variables.
3. Mounted configuration file.
4. Release defaults.

The model cannot mutate configuration.

### Required configuration groups

- Service identity.
- Database URL.
- Source root.
- State root.
- Skill catalog root.
- MCP transport and endpoint.
- Model provider and credentials.
- OpenViking transport and endpoint.
- Concurrency limits.
- Budget defaults.
- Security policy.
- Retention policy.
- Telemetry exporters.

## 10. Proposed environment variables

### Service

- `LEARNING_AGENT_INSTANCE_ID`.
- `LEARNING_AGENT_HTTP_HOST`.
- `LEARNING_AGENT_HTTP_PORT`.
- `LEARNING_AGENT_LOG_LEVEL`.

### Persistence

- `DATABASE_URL`.
- `POOL_SIZE`.
- `MIGRATION_MODE`.

### Paths

- `SOURCE_ROOT`.
- `STATE_ROOT`.
- `SKILL_ROOT`.
- `TMP_ROOT`.

### MCP

- `CBM_MCP_TRANSPORT`.
- `CBM_MCP_URL`.
- `CBM_MCP_COMMAND`.
- `CBM_MCP_TIMEOUT_MS`.
- `CBM_MCP_MAX_FRAME_BYTES`.

### Provider

- `MODEL_PROVIDER`.
- `MODEL_NAME`.
- `MODEL_API_KEY`.
- `MODEL_BASE_URL`.
- `MODEL_TIMEOUT_MS`.
- `MODEL_MAX_RETRIES`.

### OpenViking

- `OPENVIKING_ENABLED`.
- `OPENVIKING_TRANSPORT`.
- `OPENVIKING_URL`.
- `OPENVIKING_TOKEN`.
- `OPENVIKING_TIMEOUT_MS`.

### Scheduling

- `MAX_ACTIVE_RUNS`.
- `MAX_ACTIVE_RUNS_PER_REPOSITORY`.
- `LEASE_TTL_SECONDS`.
- `LEASE_RENEW_SECONDS`.

### Budgets

- `DEFAULT_MAX_TURNS`.
- `DEFAULT_MAX_MCP_CALLS`.
- `DEFAULT_MAX_SOURCE_BYTES`.
- `DEFAULT_MAX_WALL_SECONDS`.
- `DEFAULT_MAX_COST_MINOR`.

### Security

- `ALLOW_TEST_EXECUTION`.
- `ALLOW_SYMLINK_ARTIFACTS`.
- `OPENVIKING_DEFAULT_POLICY`.
- `PROMPT_AUDIT_MODE`.

## 11. Configuration validation

Reject startup when:

- Required paths overlap unsafely.
- Source root is under skill root.
- Skill root is under source root.
- State root is read-only.
- Source root is writable while strict mode requires read-only.
- Lease renew interval is not safely below TTL.
- Provider credentials are missing.
- MCP transport settings conflict.
- OpenViking is enabled without credentials or endpoint.
- Numeric budgets are negative or unbounded.
- Runtime instance ID is empty.

Warn when:

- OpenViking is disabled.
- Probe execution is disabled.
- Symlink publication is unavailable.
- Database is SQLite with concurrency above one.

## 12. Operator frontend and API

Phoenix LiveView is required for the operations frontend.

The frontend uses the same authorized application contexts as the JSON API.

PubSub notifications trigger durable projection refreshes.

The frontend exposes repository, run, worker, provider, model, route, artifact, OpenViking, settings, and audit views.

### Operator API

### `POST /v1/repositories`

Registers repository configuration.

Does not start learning automatically unless requested.

### `GET /v1/repositories`

Lists repository status and closure summary.

### `GET /v1/repositories/:id`

Returns inventory and blocker summaries.

### `POST /v1/repositories/:id/runs`

Queues a pass with budgets and optional target subsystem.

### `GET /v1/runs/:id`

Returns run state, gate, budgets, and recent events.

### `POST /v1/runs/:id/cancel`

Persists cancellation intent.

### `POST /v1/blockers/:id/resolve`

Records operator resolution evidence.

### `POST /v1/outbox/:id/retry`

Makes a failed OpenViking event eligible.

### `GET /health/live`

Reports process liveness.

### `GET /health/ready`

Reports readiness dependencies.

### `GET /metrics`

Exports metrics when enabled.

The API never accepts arbitrary tool calls.

## 13. Scheduling

The scheduler is an internal OTP process backed by SQL.

It wakes on a timer and explicit notifications.

It selects eligible queued runs.

It respects global concurrency.

It respects repository status.

It skips repositories with live leases.

It does not select blocked or complete repositories unless explicitly reactivated.

It starts workers through the dynamic supervisor.

The scheduler is not the source of truth for active work.

SQL runs and leases are authoritative.

## 14. Backpressure

Backpressure inputs:

- Active run count.
- Database pool saturation.
- Provider rate-limit state.
- MCP health.
- OpenViking backlog.
- Memory pressure.
- Cost budget window.

OpenViking backlog does not stop local learning by default.

Severe database or memory pressure pauses admission.

Provider rate limits reduce admission.

MCP unavailability blocks affected preflight work.

## 15. Graceful shutdown

Shutdown sequence:

1. Mark instance draining.
2. Stop new API admissions that create work.
3. Stop scheduler claims.
4. Notify active workers.
5. Workers finish current durable boundary or cancel.
6. Stop publisher claims.
7. Persist final heartbeats.
8. Terminate HTTP listeners.
9. Stop database last.

Shutdown has a configured deadline.

Forced termination leaves leases to expire.

Recovery reconciles orphaned work on restart.

## 16. Logging

Use structured JSON logs in production.

Required fields:

- Timestamp.
- Level.
- Event name.
- Instance ID.
- Run ID when applicable.
- Repository ID when applicable.
- Pass number when applicable.
- Gate when applicable.
- Tool operation when applicable.
- Error class when applicable.

Do not log:

- API keys.
- Authorization headers.
- Full source excerpts by default.
- Full prompts by default.
- Full model responses by default.
- Repository absolute paths in multi-tenant metrics.

## 17. Metrics

### Scheduler metrics

- Queued runs.
- Active runs.
- Admission delay.
- Lease conflicts.
- Orphaned runs.

### Learning metrics

- Pass duration.
- Gate duration.
- Outcomes per pass.
- Covered seams.
- Partial seams.
- Omitted seams.
- Open blockers.
- Closure percentage by adjudication.

### Model metrics

- Calls.
- Tokens.
- Cost.
- Latency.
- Retries.
- Guidance retries.
- Tool denials.

### MCP metrics

- Calls by operation.
- Latency.
- Timeouts.
- Reconnects.
- Pagination.
- Coverage gaps.

### Artifact metrics

- Staged generations.
- Validation failures.
- Publication duration.
- Recovery journal count.
- Parity failures.

### OpenViking metrics

- Pending events.
- Oldest event age.
- Delivery attempts.
- Delivery failures.
- Verification failures.

## 18. Tracing

Create one trace per run.

Create spans for:

- Lease claim.
- Gate execution.
- Model call.
- Tool policy.
- MCP request.
- Source read.
- Probe execution.
- Note publication.
- Artifact validation.
- Artifact activation.
- SQL result commit.
- OpenViking delivery.

Propagate correlation IDs to supported external systems.

Do not propagate secrets.

## 19. Alerts

Alert on:

- Scheduler unable to claim for a sustained period.
- Repeated database failures.
- Lease renewal failures.
- Orphaned run growth.
- Artifact publication conflicts.
- Active generation digest mismatch.
- Permanent OpenViking failures.
- Provider authentication failures.
- MCP pin mismatch spikes.
- Budget burn above configured threshold.
- Skill-volume free space low.

## 20. Health states

### Healthy

Core dependencies work.

No critical recovery backlog exists.

### Degraded

OpenViking unavailable.

Probe runner disabled.

Provider rate limited but recoverable.

### Not ready

Database unavailable.

Schema incompatible.

State or skill volume unavailable.

Recovery incomplete.

No configured model provider.

No configured MCP integration.

### Unhealthy

BEAM supervision cannot maintain required core processes.

## 21. Deployment profiles

### Development profile

Local source mount.

Local database or Docker database.

Mock provider allowed.

Mock MCP allowed.

OpenViking optional.

### Single-node production profile

One app replica with all application roles.

Phoenix LiveView is served on the configured HTTP port.

PostgreSQL or validated SQLite.

Read-only source snapshots.

External provider.

Codebase Memory endpoint.

OpenViking enabled or explicitly degraded.

### Multi-replica profile

Required as a tested scale-out profile after single-node correctness.

The same image runs role-specific containers.

Worker replicas are horizontally scalable.

Requires PostgreSQL.

Requires tested lease fencing.

Requires shared state and skill volumes or artifact service.

Requires publication lock semantics across nodes.

## 22. Supply-chain policy

Pin Hex dependencies.

Commit lock file.

Verify checksums through Hex.

Generate dependency inventory.

Scan known vulnerabilities.

Review NIF dependencies carefully.

Do not download runtime plugins.

Do not let the model select dependencies.

## 23. Privacy policy hooks

Repositories have data-classification labels.

Repositories have provider allowlists.

Repositories have OpenViking publication policies.

Source excerpt limits vary by classification.

Private repositories may require self-hosted providers.

Audit export records every external content transfer digest.

## 24. Operational acceptance

- Service runs without root.
- Source mount writes fail.
- Unknown outbound destinations fail.
- Secrets are redacted from logs.
- Readiness blocks before recovery.
- Graceful shutdown preserves durable progress.
- Forced shutdown recovers orphaned runs.
- OpenViking outage reports degraded status.
- Database outage stops admission.
- Skill-volume failure blocks publication.
- Stale workers cannot commit after lease loss.
- Metrics avoid high-cardinality source symbols.

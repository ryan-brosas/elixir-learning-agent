# Phoenix LiveView Frontend and Operations Control Plane

## 1. Requirement

A frontend is now required for version one.

The frontend is not a separate JavaScript single-page application.

The recommended implementation is Phoenix LiveView.

LiveView keeps the initial product inside one Elixir release.

Phoenix PubSub carries real-time hints to connected views.

Durable SQL projections remain the source of truth.

The JSON API and LiveView call the same application contexts.

## 2. Evidence

Context7 resolved the authoritative Phoenix documentation as `/phoenixframework/phoenix/v1_8_0`.

The Phoenix documentation demonstrates LiveView subscriptions, streams, scoped context calls, and PubSub-driven updates.

The Phoenix release documentation demonstrates `mix phx.gen.release`, `mix release`, runtime configuration, a non-root Docker runtime, and the `bin/server` release entrypoint.

This design uses those patterns without pinning an implementation version before the Mix project is created.

## 3. Frontend goals

- Make repository-learning progress understandable.
- Make workers and capacity visible.
- Make model-provider health visible.
- Let operators configure routing safely.
- Let operators queue and cancel runs.
- Let operators resolve blockers.
- Let operators inspect evidence.
- Let operators preview generated skills.
- Make OpenViking degradation visible.
- Avoid direct database administration.
- Avoid container restarts for routine capacity changes.

## 4. Frontend non-goals

- General-purpose chat.
- Source-code editing.
- Arbitrary prompt submission.
- Arbitrary tool execution.
- Arbitrary shell execution.
- Secret display.
- Database query console.
- OpenViking deletion console.
- Replacing durable audit records with ephemeral UI state.

## 5. Framework decision

### Chosen

Phoenix with LiveView, PubSub, HEEx components, and server-side contexts.

### Why

- Same language and release as the agent runtime.
- No second deployment artifact is required.
- Server-authoritative state fits durable workflow projections.
- PubSub supports low-latency operational updates.
- LiveView reconnects can rehydrate from SQL.
- Authentication and authorization remain server-side.
- Streams efficiently update worker and run lists.

### Rejected initial alternative

A separate React or Next.js frontend.

Reason:

- Adds a second toolchain.
- Adds an API compatibility boundary.
- Adds another container and release process.
- Provides little benefit for the first operations-focused product.

A separate frontend can be added later through the existing JSON API.

## 6. Information architecture

### `/`

System overview.

### `/repositories`

Repository registry and closure progress.

### `/repositories/:id`

Repository detail, pin, inventory, seams, artifacts, and pass history.

### `/runs`

Queued, active, blocked, completed, and cancelled runs.

### `/runs/:id`

Live run timeline, gate, budgets, model route, tool calls, and evidence.

### `/workers`

Worker instances, slots, leases, utilization, and drains.

### `/providers`

Provider and model profiles, health, cooldowns, limits, and routing order.

### `/artifacts`

Skill generations, validation, activation, rollback, and manifests.

### `/openviking`

Outbox backlog, remote references, retrieval verification, and retries.

### `/settings`

Versioned runtime settings and audit history.

### `/audit`

Operator actions and safety denials.

## 7. Dashboard

The dashboard shows:

- Service health.
- Database health.
- Codebase Memory health.
- OpenViking health.
- Provider health by profile.
- Active worker slots.
- Global concurrency limit.
- Queued runs.
- Active runs.
- Blocked repositories.
- OpenViking backlog.
- Estimated current cost.
- Pass throughput.
- Recent artifact publications.

Dashboard values come from application contexts.

No dashboard card computes business truth independently.

## 8. Repository list

Each row shows:

- Repository name.
- Source pin.
- Graph project.
- Repository state.
- Current pass.
- Closure progress.
- Covered seams.
- Partial seams.
- Omitted seams.
- Open blockers.
- Last activity.
- Active worker.

Operators can:

- Register a repository.
- Disable or enable a repository.
- Queue a pass.
- Open repository detail.

Registration validates path and graph configuration before persistence.

## 9. Repository detail

### Summary panel

Shows canonical source and graph identity.

### Inventory panel

Shows subsystem and seam hierarchy.

### Coverage panel

Shows parse-partial, skipped, excluded, and checked scopes.

### Learning panel

Shows pass notes and next targets.

### Skill panel

Shows active `SKILL.md` and capsule map.

### Artifact history

Shows immutable generations and validation results.

### Closure panel

Shows every closure conjunct individually.

A repository cannot display a green complete badge unless the domain closure result is true.

## 10. Run detail

The run page is the primary live operational view.

It shows:

- Run ID.
- Repository.
- Pass number.
- State.
- Gate.
- Lease holder and epoch.
- Selected subsystem.
- Current porter question.
- Model profile.
- Fallback route.
- Turn count.
- MCP call count.
- Source-read bytes.
- Probe count.
- Token usage.
- Estimated cost.
- Remaining wall time.
- Cancellation state.

### Timeline

The timeline contains durable events.

Examples:

- Run queued.
- Lease claimed.
- Index verified.
- Note published.
- Tool requested.
- Tool denied.
- Evidence recorded.
- Capsule staged.
- Validation passed.
- Artifact activated.
- OpenViking queued.
- Run completed.

Live PubSub messages tell the view to refresh or stream a durable event.

PubSub payloads are not authoritative history.

## 11. Worker page

The worker page distinguishes:

- Application replicas.
- Worker processes.
- Configured slots.
- Occupied slots.
- Draining slots.
- Repository leases.

Operators can:

- Increase global worker slots.
- Decrease global worker slots.
- Adjust per-provider limits.
- Adjust per-model limits.
- Drain a worker instance.
- Pause admissions.
- Resume admissions.

Decreasing capacity does not kill active passes by default.

It prevents replacement admission until occupancy falls below the new limit.

An explicit emergency stop is a separate action.

## 12. Provider page

Each provider profile shows:

- Provider adapter.
- Display name.
- Enabled state.
- Base URL host with secrets removed.
- Health state.
- Last successful request.
- Last failure class.
- Cooldown deadline.
- Active requests.
- Concurrency limit.
- Configured models.

Each model profile shows:

- Model identifier.
- Capability flags.
- Context limit.
- Output limit.
- Cost metadata.
- Quality tier.
- Enabled state.
- Active requests.
- Concurrency limit.
- Routing weight.
- Fallback position.

Credentials are referenced by secret names.

Credentials are never returned to the browser.

## 13. Model-route editor

Operators can create named routes.

Examples:

- `deep_learning`.
- `cheap_discovery`.
- `artifact_review`.
- `local_private`.

A route contains ordered or weighted model profiles.

A route includes required capabilities.

A route includes cost and retry limits.

A route can be enabled or disabled.

Changes are validated before activation.

Changes are versioned.

Active runs retain their pinned route revision unless an explicit failover policy applies.

## 14. Settings model

Settings are not arbitrary key-value strings.

Use typed settings schemas.

Settings groups include:

- Scheduler capacity.
- Provider capacity.
- Model capacity.
- MCP limits.
- Default run budgets.
- Artifact publication policy.
- OpenViking policy.
- Retention.

Every update records:

- Previous revision.
- New revision.
- Operator.
- Reason.
- Validation result.
- Activation timestamp.

## 15. Live update architecture

Domain contexts broadcast small change notifications after transaction commit.

Example topics:

- `system:health`.
- `repositories`.
- `repository:<id>`.
- `runs`.
- `run:<id>`.
- `workers`.
- `providers`.
- `artifacts`.
- `openviking`.

LiveViews subscribe only after the socket is connected.

On mount or reconnect, each LiveView reloads its durable projection.

On notification, it fetches changed records or applies a durable event.

A missed PubSub notification does not lose state.

## 16. LiveView modules

Proposed modules:

- `LearningAgentWeb.DashboardLive`.
- `LearningAgentWeb.RepositoryLive.Index`.
- `LearningAgentWeb.RepositoryLive.Show`.
- `LearningAgentWeb.RunLive.Index`.
- `LearningAgentWeb.RunLive.Show`.
- `LearningAgentWeb.WorkerLive.Index`.
- `LearningAgentWeb.ProviderLive.Index`.
- `LearningAgentWeb.ProviderLive.Edit`.
- `LearningAgentWeb.ArtifactLive.Index`.
- `LearningAgentWeb.ArtifactLive.Show`.
- `LearningAgentWeb.OpenVikingLive.Index`.
- `LearningAgentWeb.SettingsLive`.
- `LearningAgentWeb.AuditLive.Index`.

## 17. Components

Reusable components:

- Health badge.
- Run-state badge.
- Gate progress stepper.
- Budget meter.
- Worker-capacity meter.
- Provider-health card.
- Model-profile table.
- Lease table.
- Evidence viewer.
- Source excerpt viewer.
- Capsule preview.
- Diff viewer.
- Closure checklist.
- Confirmation modal.
- Audit-reason form.

## 18. Authorization

Every LiveView mounts with an authenticated operator scope.

Viewer pages accept viewer scope.

Mutation events require operator or administrator scope.

Provider credential changes require administrator scope.

Capacity changes require operator scope.

Publication-policy changes require administrator scope.

Server-side handlers reload the resource under the current scope.

UI hiding is not authorization.

## 19. Dangerous actions

Dangerous actions require confirmation and a reason.

Examples:

- Cancel active run.
- Emergency stop worker.
- Disable provider.
- Activate artifact rollback.
- Override blocker.
- Change external publication policy.

The UI sends an idempotency key.

The application records an audit event.

## 20. Evidence viewer

The evidence viewer distinguishes authority classes visually.

- Navigational evidence.
- Structural evidence.
- Authoritative evidence.
- Derived evidence.

It displays:

- Operation.
- Bounded arguments.
- Digest.
- Timestamp.
- Source pin.
- Coverage caveat.
- Parent evidence.

Secret and restricted bodies remain hidden.

## 21. Artifact preview

Before activation, operators can inspect:

- Proposed `SKILL.md`.
- New capsules.
- Changed capsules.
- Removed capsules.
- Loader-map-disk parity.
- Validation results.
- Pressure-test results.
- Manifest digest.

Human approval may be configured as required or optional.

The initial autonomous policy remains a user decision.

## 22. Error handling

LiveView errors produce typed user messages.

Optimistic UI does not mark durable actions complete before confirmation.

Stale settings revisions return conflict.

Lost authorization redirects safely.

Disconnected views reconnect and reload.

Long operations return immediately with a durable command ID.

## 23. Accessibility

Use semantic HTML.

All status colors include text or icons.

All actions are keyboard accessible.

Live updates use restrained ARIA announcements.

Focus moves predictably after modal actions.

Tables provide labels and captions.

## 24. Responsive behavior

Desktop is primary for evidence-rich operation.

Tablet remains fully functional.

Mobile supports monitoring and emergency actions.

Large source and diff panels scroll independently.

## 25. Frontend tests

### LiveView unit and integration tests

- Dashboard renders durable metrics.
- Repository closure cannot be forged by assigns.
- Run timeline updates after PubSub notification.
- Reconnect reloads missed events.
- Viewer cannot mutate.
- Operator can queue and cancel.
- Administrator can edit routes.
- Stale revision returns conflict.
- Secrets never render.
- Capacity decrease drains without killing active work.

### Browser tests

- Register repository.
- Queue pass.
- Follow live progress.
- Cancel pass.
- Add provider profile.
- Enable model.
- Change worker capacity.
- Inspect capsule.
- Retry OpenViking event.

## 26. Frontend observability

Track:

- Connected LiveViews.
- Mount duration.
- Event-handler duration.
- PubSub delivery count.
- Reconnect count.
- Authorization denial count.
- Stale revision conflict count.
- UI command latency.

Do not use user or repository names as metric labels.

## 27. Docker exposure

The default compose stack exposes the Phoenix endpoint on port 4000.

The browser connects to the web role.

The all-in-one profile serves LiveView and runs workers in one container.

The scale-out profile may run dedicated web and worker containers from the same image.

Web containers never need write access to source when contexts are remote, but the default shared release may retain the configured mount.

## 28. Frontend acceptance

- `docker compose up --build` starts the frontend.
- `http://localhost:4000` renders the dashboard.
- Repository, run, worker, provider, artifact, and OpenViking pages exist.
- Run updates appear without manual refresh.
- Reconnect restores current state.
- Operators can adjust capacity without restart.
- Operators can configure model profiles without exposing credentials.
- All mutations pass server-side authorization.
- No UI action bypasses domain invariants.

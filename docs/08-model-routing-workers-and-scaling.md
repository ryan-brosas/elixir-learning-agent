# Multi-Provider Models, Worker Capacity, and System Scaling

## 1. Requirement

The complete product must support multiple LLM providers.

The complete product must support multiple models per provider.

Operators must select defaults without code changes.

Operators must adjust concurrency without container restart.

Operators must add worker replicas without changing workflow semantics.

The default Docker deployment must run the whole system.

## 2. Architectural distinction

A provider is an API adapter and credential boundary.

A model profile is one configured model behind a provider.

A route is a policy over model profiles.

A worker is an OTP process executing one repository pass.

A worker slot is admission capacity.

An application replica is one BEAM node or container.

These concepts must not be collapsed.

## 3. Provider adapters

Required adapter families for the first complete release:

- OpenAI-compatible Responses or tool-calling APIs.
- Anthropic Messages tool-calling API.
- Google Gemini tool-calling API.
- Ollama or local OpenAI-compatible API.

Provider support is capability-gated.

A configured provider can expose several model profiles.

No provider is hard-coded as the permanent default.

## 4. Provider behavior

```elixir
defmodule LearningAgent.Provider do
  @callback models(provider_config()) ::
    {:ok, [DiscoveredModel.t()]} |
    {:error, ProviderError.t()}

  @callback complete(ModelRequest.t(), provider_config()) ::
    {:ok, ModelResponse.t()} |
    {:error, ProviderError.t()}

  @callback cancel(request_ref(), provider_config()) :: :ok | {:error, term()}

  @callback health(provider_config()) ::
    {:ok, ProviderHealth.t()} |
    {:error, ProviderError.t()}
end
```

Model catalog discovery is optional.

Static model profiles remain supported.

## 5. Provider profile

Fields:

- Provider profile ID.
- Adapter name.
- Display name.
- Base URL.
- Credential reference.
- Organization or project reference.
- Enabled state.
- Health state.
- Request timeout.
- Retry policy.
- Rate-limit policy.
- Maximum concurrent requests.
- TLS policy.
- Proxy policy.
- Metadata.

Secrets are resolved at call time.

Database rows store secret references, not secret values.

## 6. Model profile

Fields:

- Model profile ID.
- Provider profile ID.
- Wire model identifier.
- Display name.
- Enabled state.
- Capability set.
- Context-window limit.
- Maximum output limit.
- Default output limit.
- Tool-schema limit.
- Structured-output support.
- Streaming support.
- Input cost metadata.
- Output cost metadata.
- Cached-input cost metadata.
- Quality tier.
- Latency tier.
- Privacy tier.
- Maximum concurrent requests.
- Weight.
- Health override.

## 7. Capability model

Capabilities include:

- `tool_calls`.
- `parallel_tool_calls`.
- `structured_output`.
- `streaming`.
- `reasoning`.
- `large_context`.
- `vision`.
- `prompt_caching`.
- `request_cancellation`.

The repository-learning route requires `tool_calls`.

The runtime may deliberately disable parallel calls even when supported.

A route cannot select a model missing required capabilities.

## 8. Named routes

Recommended routes:

### `repository_learning`

High-quality model for graph reasoning and source-confirmed synthesis.

### `discovery_low_cost`

Lower-cost model for bounded candidate discovery when policy permits.

### `artifact_pressure_test`

Independent route used to test whether a capsule changes retrieval behavior.

### `private_local`

Local-only profiles for repositories that cannot leave the deployment.

### `operator_selected`

Explicit model profile pinned by an operator for one run.

The no-delegation invariant means one active learning turn is produced by one selected profile.

Routing and fallback do not create subordinate learning agents.

## 9. Route policy

A route contains:

- Route ID.
- Revision.
- Required capabilities.
- Ordered candidates or weighted pool.
- Maximum fallback count.
- Maximum total attempts.
- Cost ceiling.
- Context minimum.
- Privacy requirement.
- Enabled state.

A run pins a route revision.

A turn records the selected model profile.

Fallback selection is durable and auditable.

## 10. Routing strategies

### Explicit

Use one operator-selected model profile.

### Ordered fallback

Try candidates in configured order after classified retry exhaustion.

### Weighted healthy pool

Select among healthy profiles using configured weights and capacity.

### Cost-aware

Select the cheapest healthy model satisfying capabilities and minimum quality.

### Quality-first

Select the highest quality tier within budget.

### Privacy-constrained

Select only profiles meeting repository data policy.

Version one should implement explicit and ordered fallback first.

Weighted and cost-aware routing can follow after telemetry exists.

## 11. Fallback rules

Fallback is allowed for:

- Provider unavailability.
- Rate-limit exhaustion.
- Selected transient server failures.
- Model disabled before request start.
- Capacity unavailable beyond configured wait.

Fallback is not allowed for:

- Tool policy denial.
- Source evidence contradiction.
- Invalid repository pin.
- User cancellation.
- Budget exhaustion.
- Content policy when every candidate shares the same prohibited data policy.
- Malformed application tool schema.

## 12. Conversation continuity

Provider adapters project one canonical message history.

Tool call and result groups remain intact.

Provider-native IDs are not required by another provider unless the provider contract requires them.

Unsupported provider-specific reasoning blocks are normalized or omitted according to policy.

Temporary retry guidance remains temporary.

A fallback records why history projection is safe.

If safe projection is impossible, the run blocks instead of corrupting history.

## 13. Provider health

Health states:

- `unknown`.
- `healthy`.
- `degraded`.
- `rate_limited`.
- `open_circuit`.
- `disabled`.

Health inputs:

- Explicit probe.
- Recent classified failures.
- Retry-After deadline.
- Authentication state.
- Latency window.
- Manual override.

Health is scoped to a provider profile and optionally model profile.

One broken model does not always disable the provider.

## 14. Circuit breaker

The breaker tracks consecutive eligible failures.

Policy errors do not trip provider circuits.

Authentication failures open the provider profile immediately.

Rate limits create cooldowns honoring Retry-After.

Selected server errors increment the breaker.

A half-open probe uses one request slot.

Successful probes close the breaker.

## 15. Provider concurrency

Capacity dimensions:

- Global model requests.
- Provider-profile requests.
- Model-profile requests.
- Repository passes.
- Per-repository passes.

A request must acquire all applicable tokens.

Token acquisition order is deterministic.

Failed acquisition releases already acquired tokens.

Request tokens are monitored and released in `after` cleanup.

Provider cooldown prevents new token grants.

## 16. Worker concurrency

### Global run limit

Maximum active repository-pass workers across the deployment.

### Per-repository limit

Always one committing pass per repository.

### Per-instance slot limit

Maximum pass workers on one BEAM instance.

### Provider-aware admission

Scheduler may avoid starting work when no eligible route capacity exists.

### MCP-aware admission

Scheduler may reduce starts while Codebase Memory is degraded.

## 17. Runtime capacity settings

Typed settings:

- `global_worker_limit`.
- `instance_worker_limit`.
- `repository_worker_limit`.
- `provider_request_limits`.
- `model_request_limits`.
- `mcp_request_limit`.
- `openviking_publish_limit`.
- `admission_paused`.

Settings are stored in SQL with revisions.

Settings updates broadcast through PubSub after commit.

Each instance reconciles to the latest revision.

## 18. Capacity increase

Operator raises a limit.

The settings transaction commits.

Scheduler receives a change notification.

Scheduler immediately reevaluates queued runs.

DynamicSupervisor starts additional workers up to the new limit.

No container restart is required.

## 19. Capacity decrease

Operator lowers a limit.

The settings transaction commits.

No new worker starts above the new limit.

Existing workers enter natural drain.

Capacity becomes compliant as workers finish.

An explicit hard-stop option is separate and audited.

## 20. Adding application replicas

All replicas use the same release image.

All replicas use the same PostgreSQL database.

All replicas announce instance identity and configured roles.

All replicas use lease fencing.

Worker replicas claim queued runs transactionally.

Adding a replica increases available instance slots.

Global SQL settings still cap deployment-wide concurrency.

## 21. Instance registry

Fields:

- Instance ID.
- Node name.
- Container identity.
- Enabled roles.
- Configured slots.
- Active slots.
- Draining state.
- Started timestamp.
- Last heartbeat.
- Build version.

Expired instances are marked offline.

Their process-local work is reconciled through lease expiry.

## 22. Application roles

Supported roles:

- `web`.
- `scheduler`.
- `worker`.
- `publisher`.
- `all`.

### All role

Runs the full system in one container.

This is the default local and small deployment.

### Web role

Runs Phoenix endpoint and read contexts.

### Scheduler role

Runs durable admission.

Only one scheduler leader actively admits at a time.

### Worker role

Runs pass workers and external learning calls.

### Publisher role

Runs OpenViking outbox delivery.

Roles select children in the supervision tree.

They do not create separate codebases.

## 23. Scheduler leadership

The all-in-one single replica is trivially leader.

Multi-replica deployments require a leader lease or PostgreSQL advisory lock.

Leadership has a heartbeat and expiry.

Only the active leader admits queued runs.

Workers do not require scheduler leadership to finish active work.

A new leader resumes from durable queue state.

## 24. Docker Compose profiles

### Default profile

Services:

- `app` with `APP_ROLES=all`.
- `postgres`.

The app serves the frontend and runs scheduler, workers, and publisher.

### Scale-out profile

Services:

- `web` with `APP_ROLES=web`.
- `scheduler` with `APP_ROLES=scheduler`.
- `worker` with `APP_ROLES=worker` and scalable replicas.
- `publisher` with `APP_ROLES=publisher`.
- `postgres`.

Every app service uses the same image.

## 25. Docker scaling commands

The final implementation must support a command equivalent to:

```text
docker compose up --build -d
```

The scale-out profile must support a command equivalent to:

```text
docker compose --profile scale up -d --scale worker=4
```

Exact compose syntax is verified during implementation.

Runtime concurrency can still remain below replica capacity.

## 26. Shared storage

Single-host Compose may use named volumes for state and skills.

Worker and publisher roles require coordinated access to staging and artifact data.

PostgreSQL owns workflow truth.

The source volume is read-only in worker containers.

The skill volume is writable only where artifact publication occurs.

For multi-host scaling, replace shared local volumes with an artifact service or object storage before claiming support.

## 27. Worker assignment

Scheduler creates or selects a queued run.

A worker instance claims a run through SQL.

Claim includes lease epoch.

Worker starts one RunWorker process.

Worker heartbeats lease independently of model latency.

On completion, it releases lease and slot.

On crash, lease expires and recovery classifies the run.

## 28. Fairness

Scheduler fairness dimensions:

- Oldest eligible run.
- Repository priority.
- Tenant or group quota if added later.
- Provider capacity.
- Budget window.
- Avoid repeated selection of blocked repositories.

Version one should use oldest eligible run with repository priority.

No repository may consume more than one active committing worker.

## 29. Backpressure

Admission pauses or slows when:

- Global slots are full.
- Provider route capacity is unavailable.
- MCP is unavailable.
- Database pool is saturated.
- Memory watermark is high.
- Cost window is exhausted.

OpenViking backlog does not block learning by default.

Artifact publication conflicts block the affected repository.

## 30. Cost controls

Cost limits exist at:

- Turn.
- Run.
- Repository per day.
- Provider per hour.
- Deployment per day.

The router checks projected cost before selection.

Actual usage updates durable ledgers.

Unknown pricing is treated conservatively.

Operators can disable a model immediately for new calls.

Active requests follow cancellation support and policy.

## 31. Model selection UI

Operators can:

- Add provider profiles.
- Add model profiles.
- Enable or disable profiles.
- Test health.
- Set concurrency.
- Set quality and privacy tiers.
- Set route order.
- Set route weights.
- Pin a run to a profile.
- View recent failures and cooldowns.

Credentials are entered through a secret mechanism, not returned by the API.

## 32. Configuration examples

Conceptual provider profile:

```text
provider: anthropic-primary
adapter: anthropic
credential_ref: secret://anthropic/main
max_concurrent_requests: 8
enabled: true
```

Conceptual model profile:

```text
model_profile: learning-opus
provider: anthropic-primary
model: configured-wire-id
capabilities: [tool_calls, reasoning, large_context]
quality_tier: high
max_concurrent_requests: 4
enabled: true
```

Conceptual route:

```text
route: repository_learning
strategy: ordered_fallback
candidates: [learning-opus, learning-gemini, learning-openai]
max_fallbacks: 2
```

Wire model identifiers are configuration, not source-code constants.

## 33. Persistence additions

### `provider_profiles`

Stores adapter configuration and secret reference.

### `model_profiles`

Stores model capabilities, limits, and routing metadata.

### `model_routes`

Stores route name and active revision.

### `model_route_entries`

Stores ordered or weighted candidates.

### `runtime_settings`

Stores typed capacity revisions.

### `instances`

Stores role and heartbeat state.

### `provider_health_events`

Stores classified health changes and cooldowns.

### `capacity_leases`

Optionally stores distributed request tokens when database-backed enforcement is required.

## 34. Routing audit

Every model request records:

- Route ID and revision.
- Candidate set.
- Selected profile.
- Selection reason.
- Capacity observation.
- Health observation.
- Fallback index.
- Provider request ID.
- Usage.
- Cost.
- Terminal classification.

## 35. Failure behavior

### Provider unavailable

Try next eligible fallback within policy.

### All providers unavailable

Block run as provider unavailable.

Preserve current state and next action.

### Model disabled during queue wait

Re-route before request start.

### Model disabled during request

Do not discard a valid completed response automatically.

Record configuration race.

Apply new configuration on the next request.

### Worker limit lowered

Drain naturally.

### Worker container removed

Lease expiry and recovery preserve run state.

### Scheduler container removed

Active workers continue.

New leader resumes admission.

### Web container removed

Workers continue.

Browser reconnects to a healthy web replica.

## 36. Testing

### Router tests

- Required capability filtering.
- Explicit profile selection.
- Ordered fallback.
- Disabled profile exclusion.
- Cooldown exclusion.
- Privacy exclusion.
- Cost ceiling exclusion.
- Safe history projection.

### Capacity tests

- Global limit.
- Instance limit.
- Provider limit.
- Model limit.
- Atomic token acquisition.
- Token cleanup after crash.
- Live capacity increase.
- Draining capacity decrease.

### Replica tests

- Two workers claim different repositories.
- Two workers cannot commit the same repository.
- Scheduler leader failover.
- Worker container kill recovery.
- Web restart does not affect runs.
- Publisher scaling preserves idempotency.

### Docker tests

- Default profile boots whole system.
- Scale profile boots role services.
- Worker replica scaling registers instances.
- UI reflects added capacity.
- Read-only source mounts remain enforced.

## 37. Observability

Metrics:

- Healthy providers.
- Healthy models.
- Requests by profile.
- Fallback count.
- Route selection count.
- Provider and model saturation.
- Global worker occupancy.
- Instance worker occupancy.
- Queue wait by route.
- Capacity-setting revision.
- Draining instances.

Traces include route selection and fallback spans.

Logs include profile IDs but never credentials.

## 38. Acceptance

- At least two provider adapters can be configured simultaneously.
- At least two model profiles can be enabled simultaneously.
- A run can pin a route or explicit model profile.
- Ordered fallback works only for classified eligible failures.
- Provider limits prevent excess requests.
- Model limits prevent excess requests.
- Global worker capacity changes without restart.
- Capacity decrease drains active work.
- Adding a worker replica increases available instance capacity.
- One repository still has one committing pass.
- Default Docker Compose runs web, scheduler, workers, publisher, and database.
- Scale-out Compose uses the same release image for every role.
- The frontend exposes provider, model, worker, and route controls.

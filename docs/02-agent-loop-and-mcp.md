# Agent Loop, MCP, Model Providers, and Tool Policy

## 1. Purpose

This document specifies how the product reasons and acts.

The model does not own durable state.

The model proposes the next bounded action.

The runtime validates and executes that action.

The runtime persists observations before the next model turn.

The loop is an interpreter over typed events.

It is not an unrestricted autonomous shell.

## 2. Agent-loop responsibilities

The agent loop:

- Builds the system instruction.
- Loads the current run projection.
- Selects bounded prior evidence.
- Sends a provider-neutral model request.
- Parses text and tool calls.
- Validates tool names.
- Validates tool arguments.
- Checks policy and budget.
- Executes one accepted call.
- Normalizes the result.
- Persists the turn and observation.
- Advances the gate state when justified.
- Stops on completion, blocker, failure, cancellation, or budget.

The agent loop does not:

- Modify source repositories.
- Install dependencies.
- Create helper scripts.
- Execute arbitrary shell commands.
- Delegate learning to another model.
- Mark a repository complete directly.
- Publish unvalidated artifacts.
- Treat model confidence as evidence.

## 3. Turn protocol

### Turn input

A turn receives:

- Run ID.
- Repository ID.
- Lease epoch.
- Current run state.
- Current gate.
- Source pin.
- Graph pin.
- Selected subsystem.
- Current porter question.
- Prior tool observations.
- Unresolved evidence requirements.
- Remaining budgets.
- Cancellation status.

### Turn output

A provider response may contain:

- Assistant reasoning summary.
- Assistant content.
- Zero or more tool calls.
- Usage counters.
- Provider stop reason.
- Provider request identifier.

Internal chain-of-thought is not required or persisted.

The system stores a concise action rationale when supplied.

### Tool-call ordering

The first product version executes one tool call at a time.

Parallel model tool calls are rejected with guidance.

This preserves manual-learning semantics.

This simplifies evidence causality.

This prevents hidden batch exploration.

A later version may allow parallel calls only for independent verification operations.

### Turn completion

A turn is complete after:

1. Provider response validation.
2. Tool policy decision.
3. Tool execution or denial.
4. Durable observation insertion.
5. Usage ledger update.
6. Cancellation recheck.

## 4. Agent-loop state

### Loop states

- `building_context`.
- `calling_model`.
- `validating_response`.
- `executing_tool`.
- `persisting_observation`.
- `waiting_backoff`.
- `stopping`.

### Loop invariants

Only one provider request is active per run.

Only one tool execution is active per run.

A new model call never begins before the prior observation commits.

A denied tool call is persisted as a denial result.

A provider retry never duplicates an accepted tool execution.

A stream retry restarts from an empty response buffer.

## 5. Provider-neutral message model

### Message roles

- `system`.
- `operator`.
- `assistant`.
- `tool`.
- `temporary_guidance`.

### Content block kinds

- `text`.
- `tool_call`.
- `tool_result`.
- `citation`.
- `usage`.

### Message fields

- Message ID.
- Run ID.
- Turn number.
- Role.
- Ordered content blocks.
- Persist policy.
- Provider projection metadata.
- Created timestamp.

Temporary guidance is visible to one retry.

Temporary guidance is excluded from durable learning notes.

Provider-native identifiers are adapter metadata, not domain identifiers.

## 6. Model request

```elixir
%ModelRequest{
  run_id: run_id,
  model: model_ref,
  messages: messages,
  tools: tool_schemas,
  tool_choice: :auto,
  temperature: configured_temperature,
  max_output_tokens: limit,
  timeout_ms: timeout,
  metadata: correlation_metadata
}
```

The default temperature is a configuration decision.

The design recommends a low value for evidence extraction.

The runtime clamps provider settings to policy limits.

## 7. Model response validation

Validate that:

- The response belongs to the active provider request.
- The response is structurally complete.
- Tool call identifiers are unique within the turn.
- Tool names are registered.
- Arguments parse as JSON objects.
- Arguments satisfy the registered schema.
- No tool call exceeds current gate permissions.
- No assistant claim is treated as an observation without a tool result.

Malformed responses may receive one guidance retry.

Repeated malformed responses block the run as `provider_protocol`.

## 8. Provider behavior

```elixir
defmodule LearningAgent.Provider do
  @callback complete(ModelRequest.t()) ::
    {:ok, ModelResponse.t()} |
    {:error, ProviderError.t()}

  @callback classify(term()) :: ProviderError.t()

  @callback estimate_cost(ModelUsage.t()) :: Money.t() | :unknown
end
```

### Provider error classes

- `authentication`.
- `authorization`.
- `rate_limited`.
- `timeout`.
- `connection`.
- `server`.
- `invalid_request`.
- `context_overflow`.
- `content_policy`.
- `malformed_response`.
- `cancelled`.
- `unknown`.

### Retryability

Authentication is terminal.

Authorization is terminal.

Invalid request is terminal unless a deterministic adapter correction exists.

Context overflow invokes bounded context compaction once.

Content policy is terminal for the current prompt projection.

Rate limits may retry using provider guidance.

Timeouts may retry within budget.

Selected server errors may retry.

Unknown errors retry at most once.

### Multi-provider routing boundary

The provider-neutral loop selects a named route revision, not a hard-coded model.

A route may reference model profiles from several provider adapters.

Required adapter families are OpenAI-compatible, Anthropic, Gemini, and Ollama/local.

Each profile records capabilities, limits, costs, health, and concurrency.

Version one implements explicit selection and ordered fallback.

Fallback occurs only after typed eligible failures.

One selected model owns each turn; fallback is transport recovery, not delegated repository learning.

The complete contract is in `docs/08-model-routing-workers-and-scaling.md`.

## 9. Retry with guidance

Guidance retry differs from transient retry.

Transient retry repeats after backoff.

Guidance retry changes the next request.

### Guidance examples

- Request one tool call only.
- Return arguments as a JSON object.
- Select a graph-qualified symbol before requesting a snippet.
- Provide missing capsule sections.
- Reduce output to the remaining token budget.

### Guidance constraints

Guidance is generated deterministically when possible.

Guidance is marked temporary.

Guidance is not written into repository learning history.

Guidance retries have a separate maximum.

Guidance never weakens tool policy.

## 10. Context assembly

Context is assembled from durable state.

### Mandatory context

- Product safety instruction.
- Current gate contract.
- Repository identity.
- Source and graph pin.
- Current subsystem and question.
- Prior learning-note summary.
- Covered, partial, and uncited candidates.
- Current evidence requirements.
- Available tool schemas.
- Remaining budgets.

### Optional context

- Relevant existing capsules.
- Relevant OpenViking hits.
- Exact prior observations from this pass.
- Canonical template fragments.

### Context exclusions

- Secrets.
- Unbounded source dumps.
- Entire repository file trees when not required.
- Raw logs unrelated to the current gate.
- Temporary provider guidance from prior successful turns.
- Content from another repository lane.

### Context budgeting

Reserve tokens for model output.

Reserve tokens for tool schemas.

Prefer durable summaries over full old turns.

Never summarize decisive source excerpts before claim validation.

Keep source citations verbatim and bounded.

## 11. Tool registry

Each tool registration includes:

- Stable tool name.
- Description.
- JSON Schema.
- Allowed run states.
- Allowed gates.
- Side-effect class.
- Timeout.
- Budget cost.
- Result size limit.
- Redaction rule.
- Handler module.

### Side-effect classes

- `read_external`.
- `read_source`.
- `write_internal`.
- `stage_artifact`.
- `execute_probe`.
- `publish_external`.

The model is not directly given `publish_external` tools.

OpenViking delivery is runtime-driven after commit.

## 12. Required Codebase Memory tools

### `cbm.list_projects`

Purpose: enumerate available graph projects.

Allowed gate: live index.

Arguments: none.

Result: normalized project summaries.

### `cbm.index_status`

Purpose: establish graph identity and known coverage gaps.

Allowed gate: live index and final verification.

Required argument: project.

Optional argument: verbose.

Result includes root, branch, commit, mode, counts, freshness, partial, skipped, and excluded paths.

### `cbm.get_architecture`

Purpose: discover connected subsystems.

Allowed gate: seam selection.

Arguments include project, optional path, and bounded aspects.

Cycles are requested only when relevant.

### `cbm.search_graph`

Purpose: discover symbols and relationships.

Allowed gates: selection, confirmation, retrieval verification.

The runtime enforces pagination awareness.

If `has_more` is true, the observation records truncation.

### `cbm.trace_path`

Purpose: inspect callers, callees, data flow, or cross-service flow.

Allowed gates: selection and confirmation.

The runtime preserves cursor and query arguments.

### `cbm.get_code_snippet`

Purpose: retrieve exact source for a previously resolved symbol.

Allowed gate: source confirmation.

Policy requires a prior search observation for the qualified name.

### `cbm.check_index_coverage`

Purpose: check cited files and exhaustive scopes.

Allowed gates: confirmation and final verification.

At least one path or scope is required.

### `cbm.query_graph`

Purpose: answer complex relationships not served by search or trace.

Allowed gate: selection.

Policy requires a written reason.

The runtime enforces row limits.

## 13. MCP client architecture

### Transport behavior

```elixir
defmodule LearningAgent.MCP.Transport do
  @callback connect(keyword()) :: {:ok, state()} | {:error, term()}
  @callback request(state(), MCP.Request.t(), timeout()) ::
    {:ok, MCP.Response.t(), state()} |
    {:error, MCP.TransportError.t(), state()}
  @callback close(state()) :: :ok
end
```

### Candidate transports

- Streamable HTTP.
- Standard input/output sidecar.
- Existing host proxy for development only.

The initial production transport is a decision required from the operator.

### MCP protocol state

- `disconnected`.
- `initializing`.
- `ready`.
- `degraded`.
- `closing`.

### MCP request fields

- JSON-RPC version.
- Request ID.
- Method.
- Parameters.
- Correlation metadata outside the wire body.
- Deadline.

### MCP response handling

Correlate exact request IDs.

Reject unknown response IDs.

Ignore or log bounded notifications.

Enforce maximum frame size.

Classify server errors separately from transport errors.

Do not retry a request after uncertain side effects.

Current required CBM operations are read-only.

## 14. Graph sequencing policy

The runtime enforces a partial order.

1. `list_projects` precedes first `index_status` in a repository run.
2. `index_status` passes before architecture discovery.
3. `get_architecture` precedes seam selection.
4. `search_graph` resolves a symbol before `get_code_snippet`.
5. `trace_path` follows a resolved symbol.
6. `check_index_coverage` follows identified paths.
7. Direct source read validates graph-selected ranges.
8. Direct test read validates named tests.
9. Final retrieval reruns after artifact synthesis.

A policy denial explains the missing prerequisite.

The agent may then request the prerequisite tool.

## 15. Source reader

### Source-read request

- Repository ID.
- Expected pin.
- Repository-relative path.
- Start line.
- End line.
- Expected purpose.
- Prior graph evidence ID.

### Source-read policy

Resolve the canonical repository root.

Join and normalize the relative path.

Reject absolute paths.

Reject parent traversal.

Reject symlink escapes unless explicitly allowed and contained.

Open the file read-only.

Bound bytes and lines.

Hash the bytes.

Record file metadata.

Recheck source pin when configured.

### Read result

- Relative path.
- Requested line range.
- Actual line range.
- Content.
- SHA-256 digest.
- File size.
- Truncation flag.
- Coverage caveat link.

## 16. Test evidence

Reading a direct test is always allowed when the path is graph-selected and contained.

Executing a test is separately governed.

### Test-read evidence

Records exact test path and range.

Records test name or symbol.

Records the behavior asserted.

Records content digest.

### Test execution profiles

#### Profile `disabled`

No subprocess is launched.

The run records runner unavailable.

Deterministic artifact checks still run.

#### Profile `registered_only`

Operators pre-register exact commands per repository.

The model chooses only a command identifier.

Arguments are not model controlled.

#### Profile `sandbox_service`

A separate runner API executes approved probes.

The source mount remains read-only.

Network and resource policies are externalized.

### Recommendation

Start with `disabled` or `registered_only`.

Do not expose generic shell execution.

## 17. Internal authoring tools

### `learning.publish_note`

Creates the durable note before production.

The runtime validates required sections.

### `inventory.propose_candidate`

Adds or updates a seam candidate.

The runtime rejects cross-repository references.

### `evidence.bind_claim`

Links evidence to a proposed claim.

The runtime validates evidence authority classes.

### `artifacts.propose_capsule`

Stages one capsule proposal.

Allowed only after note publication.

### `artifacts.propose_leaf`

Stages a complete leaf projection.

Allowed only after at least one capsule proposal or closure result.

### `run.record_blocker`

Creates a typed blocker.

### `run.propose_next_targets`

Records concrete follow-up targets.

The model cannot directly activate artifacts.

## 18. Tool policy firewall

Policy evaluation order:

1. Validate run and lease.
2. Check cancellation.
3. Resolve tool registration.
4. Check current state and gate.
5. Validate JSON Schema.
6. Normalize arguments.
7. Enforce path containment.
8. Enforce call prerequisites.
9. Enforce per-tool budget.
10. Enforce global budget.
11. Classify side effect.
12. Create durable invocation record.
13. Execute handler.
14. Persist normalized result.

A denial is not an exception unless policy infrastructure failed.

## 19. Forbidden tool patterns

Reject any request to:

- Install a package.
- Invoke package managers.
- Create a script.
- Create a shell pipeline.
- Recursively list source without a selected scope.
- Read another repository.
- Modify source.
- Change source permissions.
- Start another learning model.
- Launch another agent.
- Change container configuration.
- Remove OpenViking resources.
- Delete prior evidence.
- Rewrite another repository leaf.
- Mark closure without running closure computation.

## 20. Budget model

### Counters

- Model calls.
- Model input tokens.
- Model output tokens.
- Estimated cost.
- MCP calls by operation.
- Source bytes read.
- Source files read.
- Probe executions.
- Artifact bytes staged.
- Wall-clock duration.
- Policy denials.

### Enforcement

Budget checks occur before every external call.

Usage updates commit after every external call.

Provider-reported usage overrides estimates when valid.

Unknown cost uses conservative configured estimates.

A budget cannot be increased by the model.

Operators may increase a queued or paused run budget.

## 21. Stop decisions

The runtime stops when:

- Current pass acceptance succeeds.
- Closure succeeds.
- A standing blocker is recorded.
- Cancellation is requested.
- A terminal provider error occurs.
- A safety violation threshold is exceeded.
- The run budget is exhausted.
- The lease is lost.
- Source or graph pin becomes stale.

The model may propose stop.

The runtime computes the terminal state.

## 22. Agent-loop pseudocode

```text
load durable run
verify lease epoch
while run nonterminal:
  check cancellation
  check source and graph freshness at required checkpoints
  compute current gate projection
  assemble bounded context
  reserve provider budget
  call provider
  persist provider response and usage
  if response malformed:
    classify and optionally retry with temporary guidance
  else if response has no tool call:
    interpret proposed gate or stop decision
  else:
    require exactly one tool call
    evaluate policy
    persist invocation intent
    execute tool
    persist normalized observation
  apply deterministic gate transitions
  renew lease independently
persist terminal outcome
```

## 23. Prompt contract

The system prompt states:

- One repository identity.
- One connected subsystem at a time.
- Code and tests are ground truth.
- Graph and OpenViking are discovery surfaces.
- Learning note must precede artifacts.
- Tool calls must be individual and evidence-driven.
- No installs, scripts, source edits, shell, or delegation.
- Missing capability means blocker.
- Completion is computed, not asserted.
- Current gate and exact acceptance condition.

Prompts include absolute product constraints but repository paths are represented safely.

## 24. MCP observability

Emit:

- Request count by operation.
- Latency by operation.
- Timeout count.
- Protocol error count.
- Reconnect count.
- Response bytes.
- Pagination continuation count.
- Coverage caveat count.
- Graph pin mismatch count.

Do not label metrics with repository paths or symbols.

Use run IDs in traces, not high-cardinality metric labels.

## 25. Provider observability

Emit:

- Calls by provider and model.
- Input and output tokens.
- Estimated cost.
- Latency.
- Retry count.
- Guidance retry count.
- Rate-limit delay.
- Context overflow count.
- Malformed response count.
- Tool calls proposed.
- Tool calls denied.

Redact prompts from default logs.

Store prompt bodies only in protected audit storage when enabled.

## 26. Acceptance criteria

- Unknown tools are denied.
- Wrong-gate tools are denied.
- Snippet calls without graph resolution are denied.
- Source path escapes are denied.
- Parallel tool calls are denied in version one.
- Every observation is durable before the next model call.
- Cancel-before-start is preserved.
- Transient retries do not duplicate tools.
- Guidance retries are temporary.
- Budget exhaustion blocks rather than completes.
- Provider changes do not change domain message semantics.
- MCP transport changes do not change Codebase Memory domain operations.

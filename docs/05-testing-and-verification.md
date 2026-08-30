# Testing and Verification Strategy

## 1. Testing principle

A test is valuable when it catches a realistic violation.

Each critical invariant receives a pre-fix failure scenario.

Passing a build alone does not complete the product.

Verification combines deterministic tests and live contract probes.

External dependencies are tested behind behaviors.

## 2. Test layers

- Pure domain unit tests.
- State-machine model tests.
- Database constraint tests.
- Adapter contract tests.
- MCP protocol tests.
- Provider projection tests.
- Filesystem publication tests.
- Recovery fault-injection tests.
- OpenViking outbox tests.
- End-to-end learning simulations.
- Live integration probes.
- Security tests.
- Load and soak tests.

## 3. Unit-test targets

### Closure algebra

Test an empty unresolved set.

Test one unknown seam prevents closure.

Test one partial seam prevents closure.

Test one blocked seam prevents closure.

Test one stale seam prevents closure.

Test a valid covered seam permits closure.

Test an omission without a reason prevents closure.

Test a valid omission permits closure.

Test unresolved parse-partial coverage prevents closure.

Test stale verification prevents closure.

Test nonempty next targets prevent closure.

Test artifact parity failure prevents closure.

### Evidence authority

Test graph evidence cannot satisfy source requirement.

Test OpenViking evidence cannot satisfy source requirement.

Test direct source evidence satisfies source requirement.

Test test-read caveat is explicit.

Test missing runner is not a pass.

Test contradicted evidence blocks a claim.

### Budget arithmetic

Test calls consume budget exactly once.

Test provider retries consume model-call budget.

Test guidance retries consume guidance budget.

Test failed tool policy does not consume external-call budget.

Test source bytes count actual returned bytes.

Test cost ceiling blocks before next provider call.

### Path containment

Test normal relative path.

Test absolute path rejection.

Test parent traversal rejection.

Test encoded traversal rejection.

Test symlink escape rejection.

Test contained symlink according to policy.

Test race metadata mismatch.

## 4. Run-state transition tests

Test every allowed transition.

Test every forbidden transition.

Test terminal states are terminal.

Test note-published requires note row.

Test synthesis requires note-published.

Test publishing requires validation.

Test completion requires result transaction.

Test cancellation from every nonterminal state.

Test orphaning only after worker or lease loss.

Test stale epoch rejects transitions.

## 5. Property-based state-machine testing

Generate event sequences containing:

- Queue.
- Claim.
- Cancel.
- Start preflight.
- Publish note.
- Record evidence.
- Stage artifacts.
- Validate.
- Activate.
- Complete.
- Expire lease.
- Crash worker.
- Retry delivery.

Properties:

- At most one active lease epoch.
- No artifact before note.
- No completed run with failed mandatory gate.
- Cancellation intent never flips from true to false.
- Stale epoch never commits.
- Terminal outcome occurs at most once.
- Outbox intent survives successful pass commit.

Shrink failures to minimal event sequences.

## 6. Database constraint tests

Attempt duplicate repository slug.

Attempt duplicate repository pass number.

Attempt duplicate tool call ID.

Attempt duplicate outbox idempotency key.

Attempt artifact set without note.

Attempt invalid run state.

Attempt omitted inventory item without reason.

Attempt terminal run without finish timestamp.

Attempt overlapping lease claim.

Verify each failure is caught by the database or changeset.

## 7. Lease tests

### Claim

One worker claims an eligible repository.

Second worker cannot claim a live lease.

Expired lease can be replaced.

Replacement increments epoch.

### Renew

Current holder renews.

Wrong holder cannot renew.

Stale epoch cannot renew.

Renewal extends expiry.

### Release

Current holder releases with outcome.

Release is idempotent.

Wrong epoch cannot release.

### Fencing

Worker A loses lease.

Worker B claims next epoch.

Worker A attempts run update.

Update affects zero rows.

Worker A terminates.

## 8. Cancel-before-start tests

Create queued run.

Request cancellation before claim.

Claiming process observes cancellation.

Worker never calls provider.

Worker never calls MCP.

Run terminates cancelled.

Repeated cancel remains idempotent.

Cancel of unknown run returns not found without creating arbitrary state unless API contract says otherwise.

## 9. Provider adapter contract tests

Every provider adapter must:

- Project system messages correctly.
- Project tool schemas correctly.
- Preserve tool call identifiers.
- Normalize usage.
- Normalize stop reasons.
- Classify authentication errors.
- Classify rate limits.
- Classify context overflow.
- Classify malformed responses.
- Honor timeout.
- Honor cancellation.
- Redact credentials.

Use recorded fixtures with secrets removed.

Live provider tests are opt-in.

## 10. Retry tests

Transient 429 honors retry guidance.

Transient 500 uses bounded backoff.

Authentication error does not retry.

Invalid request does not sleep-retry.

Context overflow invokes compaction once.

Malformed tool arguments receive one guidance retry.

Repeated malformed arguments block.

Stream retry discards partial response.

Tool execution does not repeat after provider retry.

## 11. Agent-loop tests

No-tool assistant response proposes a valid next decision.

Unknown tool is denied.

Wrong-gate tool is denied.

Parallel tool calls are denied.

Valid single tool call executes.

Observation commits before next turn.

Cancellation between model and tool prevents execution.

Cancellation after tool persists result then stops.

Budget exhaustion stops before call.

Lease loss stops before call.

## 12. Tool-policy tests

Reject package manager names.

Reject command strings.

Reject source writes.

Reject cross-repository IDs.

Reject OpenViking deletion.

Reject arbitrary publication.

Reject unbounded graph query rows.

Reject snippet before search.

Reject direct read before graph selection unless coverage fallback policy permits it.

Accept exact coverage fallback for parse-partial range.

## 13. MCP protocol tests

### Framing

Decode complete JSON-RPC response.

Buffer split frames.

Reject oversized frame.

Reject invalid JSON.

Reject unknown response ID.

Handle notification separately.

### Lifecycle

Initialize connection.

Handle server capability response.

Reconnect after transport crash.

Fail pending requests on disconnect.

Do not correlate stale response after reconnect.

### Timeouts

Request timeout returns typed error.

Late response is discarded.

Cancellation removes pending correlation.

## 14. Codebase Memory adapter tests

Normalize `list_projects`.

Normalize `index_status`.

Preserve parse-partial ranges.

Preserve skipped and excluded paths.

Detect root mismatch.

Detect branch mismatch.

Detect commit mismatch.

Preserve `has_more` from search.

Preserve trace cursor.

Require qualified symbol for snippet.

Require paths or scopes for coverage.

Bound query-graph rows.

## 15. Source-reader tests

Read exact lines.

Read final line without newline.

Report truncation.

Hash exact bytes.

Reject invalid UTF-8 according to configured policy.

Handle large file limit.

Handle file removal during read.

Handle source pin change.

Handle parse-partial range.

Never write source.

## 16. Learning-note tests

Reject note missing architecture section.

Reject note missing covered-partial-uncited list.

Reject note missing porter questions.

Reject note missing selected subsystem.

Publish SQL content first.

Recover file after crash before rename.

Recover SQL status after file rename.

Block conflicting file content.

Ensure note precedes artifact timestamps and causal references.

## 17. Capsule validator tests

Reject missing capsule-v2 marker.

Reject missing source.

Reject missing question.

Reject missing path or symbol.

Reject missing signature.

Reject missing data shape.

Reject missing decisive source.

Reject missing flow.

Reject missing invariant.

Reject missing probe.

Reject missing retrieve call.

Reject missing verdict.

Reject evidence digest mismatch.

Reject wrong repository source.

Reject stale pin.

Accept canonical valid capsule.

## 18. Leaf parity tests

Loader entry without map entry fails.

Map entry without loader entry fails.

Reference file without loader entry fails.

Loader entry without file fails.

Duplicate basename fails.

Unexpected Markdown file policy is explicit.

Path and basename aliases normalize once.

Valid bidirectional set equality passes.

## 19. Behavior pressure tests

### RED condition

Run a realistic porting question without the new capsule in retrieval scope.

Expected result misses the required invariant or selects the wrong primitive.

Record the observed failure.

### GREEN condition

Add the new capsule.

Run the same question.

Expected result retrieves the exact capsule and preserves the invariant.

Run twice when a model runner is available.

### Adversarial condition

Use a related but misleading query.

Expected result does not load an irrelevant capsule.

### No-runner condition

Record runner unavailable.

Run deterministic content and retrieval checks.

Do not label the model pressure test passed.

## 20. Artifact staging tests

Stage complete generation.

Verify manifest digest.

Reject extra executable file.

Reject symlink escape.

Reject content changed after validation.

Reject stale lease before activation.

Ensure active leaf remains unchanged after staging failure.

## 21. Publication fault injection

Inject crash after journal prepared.

Inject crash after old directory backup.

Inject crash after new activation.

Inject crash after destination verification.

Inject crash after SQL active-generation update.

Inject crash before journal commit.

For each point, restart recovery.

Assert one valid active generation.

Assert no silent data loss.

Assert conflicts block visibly.

## 22. Symlink strategy tests

Probe whether skill host discovers symlinked leaves.

Atomically swap symlink.

Verify old readers see old or new generation only.

Verify rollback.

Verify broken link reports not ready.

Skip strategy when volume disallows symlinks.

## 23. Directory replacement tests

Backup existing leaf.

Activate staged leaf.

Verify digest.

Remove backup after retention.

Crash between each operation.

Recover deterministically.

Measure missing-path window.

Document host-reader behavior.

## 24. Outbox tests

Pass transaction inserts all required events.

Duplicate transaction cannot duplicate idempotency keys.

Publisher claims pending event.

Second publisher cannot claim live event.

Expired claim can be recovered.

Transient failure schedules retry.

Permanent failure records terminal delivery failure.

Delivered event stores remote reference.

Verification event follows delivery.

OpenViking outage leaves pass locally complete.

## 25. OpenViking adapter tests

Normalize add response.

Normalize find response.

Normalize read response.

Redact authentication headers.

Enforce destination prefix.

Reject unsupported URI.

Handle semantic processing delay.

Handle no search hit.

Handle wrong search hit.

Verify expected symbol or content digest.

## 26. Recovery tests

Orphan preflight run requeues.

Orphan note-drafting run resumes safely.

Orphan after note publication preserves note.

Orphan during source read retries read.

Orphan after tool result commit continues next turn.

Orphan with uncertain artifact activation reconciles first.

Orphan after pass commit does not duplicate pass.

Orphan with pending outbox leaves event deliverable.

## 27. Staleness tests

Source HEAD changes before preflight.

Graph HEAD mismatches source.

Source changes after note.

Source changes after evidence.

Source changes before publication.

Template version changes.

Coverage digest changes.

Affected claims become stale.

Repository completion reopens.

Unaffected digest-identical evidence remains valid according to policy.

## 28. Security tests

Prompt injection requests shell.

Prompt injection requests source edit.

Prompt injection requests secret read.

Prompt injection requests another repository.

Prompt injection requests OpenViking deletion.

All are denied by deterministic policy.

Test SSRF endpoint validation.

Test log redaction.

Test artifact secret scanning.

Test read-only source mount in container.

Test non-root runtime.

Test dropped capabilities.

## 29. API tests

Unauthenticated access denied.

Viewer cannot queue.

Operator can queue allowed repository.

Operator cannot register path outside source root.

Duplicate queue idempotency works.

Cancel is idempotent.

Run status returns current gate.

Evidence body access follows authorization.

Metrics endpoint policy is explicit.

Health endpoints return expected states.

### Current browser/model dogfood gates

- `/` renders the browser playground with restrictive response headers.
- `/v1/models` denies unauthenticated access in protected mode, permits local dogfood mode, and never returns the configured API key.
- `/v1/models/test` requires operator authorization in protected mode, allows local dogfood mode, allowlists ephemeral URL/key/model fields, enforces bounded input, and returns normalized provider output without returning the API key.
- Provider tests run keyless through an injected transport and cover malformed responses.

## 30. End-to-end fixture repository

Create a small immutable fixture repository in test assets.

Include:

- Two connected subsystems.
- One reusable retry seam.
- One product-specific omission.
- One direct test.
- One parse-partial simulation fixture.
- One skipped-file simulation fixture.
- One misleading source comment.
- One changed commit for staleness.

Index it with a test MCP stub or live test instance.

Run multiple passes.

Verify note-first ordering.

Verify capsule output.

Verify closure only after every seam adjudicates.

## 31. Deterministic MCP stub

The stub supports scripted responses for:

- Project list.
- Index status.
- Architecture.
- Search pagination.
- Trace cursors.
- Snippets.
- Coverage.
- Protocol failures.
- Delays.
- Disconnects.

The stub records call order.

Tests assert the mandated discovery sequence.

## 32. Deterministic model stub

The stub emits scripted turns.

Scenarios include:

- Valid single calls.
- Unknown tool.
- Parallel calls.
- Malformed arguments.
- Repeated malformed response.
- Provider timeout.
- Rate limit.
- Context overflow.
- Stop proposal.

The stub records messages and temporary guidance.

## 33. Live integration matrix

### Codebase Memory live probe

- List projects.
- Read index status for a fixture project.
- Search a known symbol.
- Trace the symbol.
- Fetch snippet.
- Check coverage.

### Model live probe

- Request one harmless registered tool.
- Verify normalized tool call.
- Verify usage accounting.

### OpenViking live probe

- Add one disposable planning fixture when explicitly allowed.
- Find a known symbol.
- Read the hit.
- Do not remove resources without explicit confirmation.

Live probes are never required in unit CI.

## 34. Load tests

Queue many repositories.

Verify admission limit.

Simulate slow provider.

Simulate slow MCP.

Build OpenViking backlog.

Measure database pool saturation.

Measure scheduler fairness.

Verify one run per repository.

Verify cancellation latency.

## 35. Soak tests

Run repeated passes for several hours.

Inject intermittent provider failures.

Inject intermittent MCP disconnects.

Restart app periodically.

Verify no leaked processes.

Verify no unbounded mailbox growth.

Verify lease renewal remains timely.

Verify outbox eventually drains.

Verify disk usage follows retention.

## 36. Performance budgets

Define before implementation acceptance:

- API p95 latency excluding external operations.
- Scheduler claim latency.
- Maximum recovery startup duration.
- Maximum memory per active run.
- Maximum context assembly duration.
- Maximum publication activation window.
- Maximum cancellation observation delay.

Values require user workload input.

## 37. CI gates

### Fast gate

- Format.
- Compile with warnings as errors.
- Unit tests.
- Static analysis.
- Dependency audit.

### Database gate

- Migrations up.
- Constraint tests.
- Transaction tests.
- PostgreSQL integration.

### Protocol gate

- MCP stub contract.
- Provider fixtures.
- OpenViking adapter fixtures.

### Recovery gate

- Publication fault matrix.
- Lease fencing.
- Orphan recovery.

### Container gate

- Build image.
- Run as non-root.
- Check read-only root.
- Check health.
- Check source mount write denial.

### Optional live gate

- Codebase Memory.
- Model provider.
- OpenViking.

## 38. Release acceptance ledger

Before release, prove:

- All run states covered.
- All gate states covered.
- All failure classes covered.
- Cancel-before-start covered.
- Lease fencing covered.
- Note-first crash points covered.
- Artifact activation crash points covered.
- Outbox duplicate delivery covered.
- Closure negative cases covered.
- Source read-only enforcement covered.
- Tool policy injection cases covered.
- OpenViking degraded behavior covered.
- Migration and restore covered.

## 39. Manual exploratory checks

Register a fixture repository.

Queue one pass.

Observe gate progression.

Cancel before claim.

Cancel during MCP wait.

Restart during note publication.

Restart during artifact activation.

Disable OpenViking.

Resolve a blocker.

Change repository pin.

Observe completion reopen.

## 40. Definition of done

A milestone is done only when:

- Named observable behavior works.
- Targeted tests pass.
- Direct fault probes pass.
- Public modules and configuration exist.
- Documentation matches behavior.
- No unresolved P0 or P1 verification findings remain.
- Evidence includes commands and outputs.

A build by itself is not completion.

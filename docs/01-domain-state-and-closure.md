# Domain, State Machines, Evidence, and Closure

## 1. Domain vocabulary

### Repository

A source checkout or immutable source snapshot admitted for learning.

A repository has a stable internal identifier.

A repository has a canonical path or source locator.

A repository has a configured Codebase Memory project.

A repository has a current target pin.

### Repository pin

A tuple of repository root, branch, commit, and optional dirty-state policy.

A pin identifies the source generation studied by a run.

A pin change may stale prior claims.

### Learning run

One durable attempt to execute one repository pass.

A run owns one repository identifier.

A run owns one expected source pin.

A run owns one lease epoch.

### Pass

A bounded learning and production batch.

A successful pass normally produces five to eight durable outcomes.

A pass may produce fewer outcomes only with closure or blocker evidence.

### Subsystem

A connected architectural region selected from graph and source evidence.

A subsystem is not inferred solely from directory structure.

### Seam

One reusable behavioral contract and one precise porting question.

A seam is the unit of capsule production.

### Claim

A bounded statement about source behavior.

A claim has one or more source anchors.

A claim has an evidence classification.

### Pass observation

An immutable, bounded record of what one pass observed at one repository pin.

It binds repository/run/pass/pin identity, source paths, direct evidence, model identity, coverage, unresolved items, and omissions. Later passes consume a bounded projection of these facts, never complete recent note bodies.

### Learning note work record

A durable note-first publication record used for causal ordering and crash recovery.

It is not cumulative repository memory and its full body is not fed into later passes.

### Foundation capsule

An immutable accepted seam record for one pin, rendered as a canonical capsule-v2 Markdown reference. Its deterministic identity comes from the seam boundary, not the pass number.

### Foundation projection

The complete `<slug>-foundation` loader, capsule map, and references derived from all accepted capsules at exactly one repository pin.

### Evidence

An immutable observation collected from a named surface.

### Adjudication

A durable decision about a subsystem or seam.

### Closure

A computed state indicating no unresolved reusable seam remains within the pinned repository scope.

### Blocker

A named missing capability or unresolved contradiction that prevents a gate.

### Omission

A reviewed scope item that is intentionally not converted into a reusable capsule.

### Staleness

A condition where evidence no longer matches the active source or graph pin.

## 2. Identifier types

### Repository ID

Use a generated UUID.

Never use a mutable path as the primary key.

### Run ID

Use a generated UUID.

The run ID is also the cancellation key.

### Pass number

Use a repository-local monotonic integer.

A unique constraint covers repository ID and pass number.

### Lease epoch

Use a monotonic integer per repository.

A worker must present the active epoch on every protected state transition.

### Evidence ID

Use a generated UUID.

Evidence content also receives a SHA-256 digest.

### Artifact set ID

Use a generated UUID.

Artifact contents receive a manifest digest.

### Outbox key

Use a deterministic key derived from repository, pass, artifact digest, and destination URI.

## 3. Repository lifecycle

### Repository states

- `registered`.
- `index_unknown`.
- `index_ready`.
- `active`.
- `complete`.
- `blocked`.
- `stale`.
- `disabled`.

### `registered`

Configuration exists.

Source identity has not yet been verified.

### `index_unknown`

Source identity is known.

The Codebase Memory project has not been verified.

### `index_ready`

Project root, branch, commit, and coverage metadata were observed.

### `active`

At least one run is queued or executing.

### `complete`

The closure predicate is true for the current pin.

### `blocked`

A standing blocker prevents progress.

### `stale`

The current source pin differs from evidence used by completion.

### `disabled`

Operators have prevented admission.

### Repository transitions

`registered -> index_unknown` after source registration.

`index_unknown -> index_ready` after successful index verification.

`index_ready -> active` after run admission.

`active -> index_ready` after a nonterminal pass with next targets.

`active -> complete` after closure succeeds.

`active -> blocked` after a standing blocker.

`complete -> stale` after a pin change.

`blocked -> index_ready` after blocker resolution.

`stale -> index_unknown` before re-index verification.

Any non-disabled state may transition to `disabled` by operator action.

`disabled` may return to `index_unknown` after explicit enablement.

## 4. Run lifecycle

### Run states

- `queued`.
- `claimed`.
- `preflight`.
- `note_drafting`.
- `note_published`.
- `exploring`.
- `evidence_gathering`.
- `synthesizing`.
- `validating`.
- `publishing`.
- `recording_result`.
- `completed`.
- `partial`.
- `blocked`.
- `failed`.
- `cancel_requested`.
- `cancelled`.
- `orphaned`.

### `queued`

The run is durable but owns no lease.

### `claimed`

The run owns a repository lease and epoch.

### `preflight`

The worker verifies source, graph, prior state, and policy.

### `note_drafting`

The model or deterministic renderer is preparing the learning note.

### `note_published`

The note exists durably in SQL and the configured work-record output.

### `exploring`

The worker executes graph-led seam discovery.

### `evidence_gathering`

The worker confirms source, tests, coverage, and probes.

### `synthesizing`

The model proposes capsule and leaf content.

### `validating`

Deterministic validators and pressure tests run.

### `publishing`

A verified generation is being activated.

### `recording_result`

The run commits pass results, next targets, and outbox rows.

### Terminal success states

`completed` means a valid production pass committed.

`partial` means durable learning exists but full pass acceptance did not.

### Terminal non-success states

`blocked` means a named external or policy blocker prevented a gate.

`failed` means an unrecoverable internal error occurred.

`cancelled` means cancellation was observed and persisted.

### Recovery state

`orphaned` means the worker disappeared or lease expired while nonterminal.

### Transition invariants

Only `queued` may become `claimed`.

Only a valid lease holder may leave `claimed`.

No state may become `note_published` without a committed note row.

No state may become `synthesizing` before `note_published`.

No state may become `publishing` before deterministic validation passes.

No state may become `completed` before result transaction commit.

Cancellation may be requested from any nonterminal state.

Cancellation intent is stored even before claim.

Terminal states never retry automatically without a new run ID.

## 5. Gate lifecycle

Each run creates gate records.

### Gate names

- `live_index`.
- `seam_selection`.
- `source_test_confirmation`.
- `production_batch`.
- `behavior_pressure_test`.
- `membership_and_publish`.
- `final_verification`.
- `openviking_sync`.

### Gate states

- `pending`.
- `running`.
- `passed`.
- `blocked`.
- `failed`.
- `stale`.

### Gate result rule

A gate result includes evidence identifiers.

A passed gate cannot have an empty evidence set.

A blocked gate includes at least one blocker identifier.

A stale gate includes the conflicting active pin.

The OpenViking gate may be degraded without changing local artifact success.

## 6. Inventory model

The inventory prevents capsule-count completion.

### Inventory node kinds

- `repository`.
- `subsystem`.
- `module`.
- `seam`.
- `coverage_scope`.

### Inventory edge kinds

- `contains`.
- `depends_on`.
- `calls`.
- `inherits`.
- `implements`.
- `related_to`.
- `candidate_for`.

Graph-derived edges are navigational evidence.

Source-confirmed edges may be authoritative evidence.

### Inventory discovery status

- `unknown`.
- `discovered`.
- `adjudicating`.
- `adjudicated`.
- `stale`.

### Seam adjudication status

- `unknown`.
- `candidate`.
- `covered`.
- `partial`.
- `omitted`.
- `blocked`.
- `stale`.

### Covered seam requirements

A covered seam has a precise porting question.

A covered seam has at least one decisive source anchor.

A covered seam has exact coverage evidence for cited paths.

A covered seam has direct test evidence or a named caveat.

A covered seam has a deterministic probe result.

A covered seam has a valid capsule-v2 artifact.

A covered seam has a successful live retrieval result.

### Partial seam meaning

The system learned a useful fact.

At least one acceptance requirement remains missing.

Partial seams always become next-pass targets.

### Omitted seam requirements

An omission has a reason code.

An omission has reviewer evidence.

An omission is scoped to a source pin.

An omission does not conceal an unresolved reusable behavior.

### Omission reason codes

- `not_reusable`.
- `product_specific`.
- `generated_code`.
- `vendored_code`.
- `data_only`.
- `duplicate_contract`.
- `superseded_contract`.
- `outside_declared_scope`.
- `license_restricted`.
- `intentionally_excluded`.

`outside_declared_scope` cannot support whole-repository completion unless the scope itself is explicitly accepted.

### Blocked seam reason codes

- `index_unavailable`.
- `index_stale`.
- `coverage_gap`.
- `source_unavailable`.
- `test_unavailable`.
- `probe_runner_unavailable`.
- `provider_budget`.
- `policy_denial`.
- `contradictory_evidence`.
- `artifact_conflict`.

## 7. Evidence taxonomy

### Navigational evidence

- Architecture overview.
- Graph search result.
- Graph trace result.
- Semantic similarity edge.
- Graph cluster membership.
- OpenViking retrieval hit.

Navigational evidence selects where to inspect.

Navigational evidence cannot prove behavior alone.

### Structural evidence

- Index status.
- Graph root.
- Graph branch.
- Graph HEAD.
- Node count.
- Edge count.
- Coverage report.
- Parse-partial range.
- Skipped path.
- Intentional exclusion.

Structural evidence establishes index identity and caveats.

Structural evidence cannot prove runtime behavior alone.

### Authoritative evidence

- Direct source excerpt.
- Direct test excerpt.
- Existing repository-owned test result.
- Deterministic probe result.
- Artifact validator result.
- Filesystem manifest hash.

### Derived evidence

- Closure query result.
- Loader-map-disk parity result.
- Artifact pressure-test result.
- Staleness comparison.

Derived evidence records its input evidence identifiers.

## 8. Evidence record fields

Every evidence record includes:

- Evidence ID.
- Repository ID.
- Run ID.
- Pass number.
- Source pin.
- Evidence kind.
- Authority class.
- Tool or adapter name.
- Operation name.
- Normalized arguments.
- Request digest.
- Response digest.
- Bounded response body or artifact pointer.
- Observation timestamp.
- Coverage caveat.
- Parent evidence IDs.
- Redaction status.
- Verification status.

Secrets never appear in normalized arguments.

Large source bodies are stored in content-addressed blobs.

## 9. Claim model

A claim is smaller than a capsule.

A capsule may contain multiple linked claims.

### Claim fields

- Claim ID.
- Seam ID.
- Statement.
- Behavioral boundary.
- Source symbol.
- Source path.
- Source line range.
- Source digest.
- Confidence annotation.
- Authority status.
- Staleness status.

Model confidence is descriptive only.

Model confidence never replaces evidence requirements.

### Claim authority states

- `proposed`.
- `source_confirmed`.
- `test_confirmed`.
- `probe_confirmed`.
- `contradicted`.
- `stale`.

A publishable claim is source confirmed.

A fully covered claim is source confirmed plus test or explicit caveat plus probe.

Contradicted claims block the containing seam.

## 10. Closure algebra

Define the active pin as `P`.

Define inventory items at pin `P` as `I(P)`.

Define reusable seam candidates at pin `P` as `S(P)`.

Define unresolved states as:

```text
U = {unknown, candidate, partial, blocked, stale}
```

Define terminal accepted states as:

```text
T = {covered, omitted}
```

Repository closure is true only if every conjunct is true.

### C-001 Pin agreement

The source pin equals the graph pin.

### C-002 Full inventory adjudication

Every required inventory item is adjudicated.

### C-003 Seam terminality

Every seam candidate has a state in `T`.

### C-004 Covered evidence

Every covered seam satisfies all covered-seam requirements.

### C-005 Omission evidence

Every omitted seam has an accepted reason and evidence.

### C-006 Coverage resolution

No cited path has unresolved parse-partial or skipped status.

### C-007 Exhaustive scope coverage

Every configured repository scope has a completed coverage check.

### C-008 No stale evidence

Every closure input matches pin `P`.

### C-009 Artifact parity

Every covered seam maps to exactly one capsule.

Every capsule maps to exactly one loader entry.

Every loader entry maps to exactly one map entry.

Every map entry resolves to one on-disk file.

### C-010 Verification freshness

Final verification ran after the latest artifact generation.

### C-011 No standing blocker

No repository or seam blocker remains open.

### C-012 Next targets empty

The durable next-target list is empty.

### Closure formula

```text
closed(P) =
  pin_agreement(P)
  AND inventory_adjudicated(P)
  AND all_seams_terminal(P)
  AND covered_evidence_valid(P)
  AND omissions_valid(P)
  AND coverage_resolved(P)
  AND scopes_checked(P)
  AND no_stale_inputs(P)
  AND artifact_parity(P)
  AND verification_fresh(P)
  AND no_open_blockers(P)
  AND next_targets_empty(P)
```

The formula is computed by application code and cross-checked with a SQL query.

The formula result is persisted with input digests.

A model cannot directly set `complete`.

## 11. Exhaustiveness without false proof

The graph supplies a starting inventory.

The index status supplies known gaps.

Coverage scopes enumerate excluded and skipped paths.

Architecture clusters suggest subsystem boundaries.

Source confirms boundaries and behavior.

Tests confirm observable invariants.

A model adjudicates reusability.

Deterministic closure checks ensure no item is silently forgotten.

The system records known unknowns.

The system never turns absence from a graph into proof of absence from source.

For negative claims, a source scope check is mandatory.

For parse-partial regions, bounded direct reads are mandatory.

For skipped files, the run either gains a valid source observation or records a blocker or omission.

## 12. Staleness model

### Staleness triggers

- Source commit changes.
- Source root changes.
- Branch changes.
- Graph generation changes with a mismatched pin.
- Coverage metadata changes.
- Capsule source digest no longer matches.
- Direct test digest no longer matches.
- Canonical template version changes incompatibly.

### Staleness propagation

A changed source anchor stales its claim.

A stale claim stales its seam.

A stale seam stales its capsule.

A stale capsule stales artifact parity.

Any stale closure input stales repository completion.

### Revalidation

Revalidation begins with index status.

Revalidation computes changed paths when available.

Revalidation never assumes an unchanged graph node means unchanged source.

Affected seams return to candidate or partial.

Unaffected seams retain evidence only when content digests remain valid.

## 13. Cancellation model

Cancellation intent is durable.

`request_cancel(run_id)` upserts cancellation intent.

Claiming a run never overwrites existing intent.

A worker checks cancellation before every external call.

A worker checks cancellation after every external call.

A worker checks cancellation before publication.

A worker checks cancellation before terminal result commit.

Cancellation during model streaming discards the partial model turn.

Cancellation during artifact staging leaves the generation inactive.

Cancellation during activation invokes publication recovery.

Cancellation during OpenViking delivery leaves the outbox pending.

### Cancel-before-start invariant

A cancellation request may arrive before the run worker exists.

Run registration uses preserve-existing semantics.

No startup transition writes `cancel_requested = false` over an existing true value.

## 14. Retry model

Retries are boundary-specific.

### Transient retry

Examples include 429, timeout, connection reset, and selected 5xx errors.

Transient retries use bounded exponential backoff with jitter.

### Guidance retry

A structurally invalid model response may receive one temporary corrective message.

The corrective message is not persisted as user learning content.

The corrective retry consumes a separate guidance budget.

### Terminal no-retry

Examples include authentication failure, policy denial, invalid repository pin, unsupported schema, and context overflow without a safe compaction path.

### Side-effect retry rule

Before retrying a side effect, reconcile whether the previous attempt succeeded.

OpenViking uses an idempotency key when supported.

Filesystem publication uses journal state and digests.

SQL transitions use compare-and-set predicates.

## 15. Concurrency model

Only one active lease exists per repository.

Global concurrency is configurable.

A worker owns one repository and one pass.

A repository leaf has one publication lock.

OpenViking publisher concurrency is separate from learning concurrency.

Database writes do not depend on process-local mutexes.

Lease expiry does not itself authorize two workers to commit.

Lease epoch fencing rejects stale workers.

### Lease fields

- Repository ID.
- Holder instance ID.
- Run ID.
- Epoch.
- Claimed at.
- Renewed at.
- Expires at.
- Released at.
- Terminal outcome.

### Lease transition rule

Claim increments epoch.

Every protected write includes repository ID, run ID, and epoch.

A stale epoch update affects zero rows and terminates the stale worker.

## 16. Pass outcome model

### `production_pass`

Five to eight verified outcomes were published.

### `closure_pass`

Fewer outcomes were published because no uncited reusable seam remains.

### `partial_pass`

Useful learning was persisted but production acceptance was incomplete.

### `blocked_pass`

A named blocker prevented required gates.

### `cancelled_pass`

Cancellation was honored.

### `failed_pass`

An internal unrecoverable error occurred.

Every outcome includes exact changed paths and next targets.

## 17. Acceptance invariants

- A run cannot own two repositories.
- A repository cannot have two active lease epochs.
- A capsule cannot exist without a source-confirmed seam.
- An artifact set cannot exist without a committed note.
- A completed run cannot have failed mandatory gates.
- A complete repository cannot have unresolved seams.
- A stale worker cannot publish.
- A model cannot invoke an unregistered tool.
- A graph result cannot be stored as authoritative source evidence.
- An OpenViking hit cannot satisfy a source confirmation requirement.
- A missing test runner cannot be recorded as a passing test.
- A skipped index path cannot disappear from closure accounting.
- A reasoned omission cannot be silently converted to covered.
- A failed publish cannot advance the active generation.
- An uncertain external side effect must be reconciled.

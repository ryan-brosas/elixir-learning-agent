# Persistence, Artifact Publication, Recovery, and OpenViking

## 1. Purpose

This document specifies durable state and side-effect ordering.

The database stores workflow truth.

The filesystem stores source mounts, staged generations, notes, and skills.

OpenViking stores a semantic copy of pass outputs.

No single external surface is trusted to reconstruct all state.

## 2. Persistence choice

### Recommended baseline

Use PostgreSQL for the first production profile.

Reasons:

- Transactional updates.
- Strong uniqueness constraints.
- Row locking.
- Lease claim queries.
- JSON support.
- Reliable migrations.
- Future multi-replica operation.

### Alternative appliance profile

Use SQLite in WAL mode for one process and one node.

The domain API remains unchanged.

SQLite support is not assumed until tested against all lease and outbox invariants.

### Decision status

Database choice requires user confirmation.

The design uses SQL semantics common to both when practical.

## 3. Database ownership

`LearningAgent.Repo` owns database connectivity.

Context modules own queries for their aggregates.

Run workers call context functions.

Run workers do not compose SQL strings.

Migrations are release artifacts.

The service does not auto-downgrade schemas.

## 4. Proposed tables

### `repositories`

Purpose: registered source identities.

Fields:

- `id uuid primary key`.
- `slug text not null`.
- `display_name text not null`.
- `source_locator text not null`.
- `canonical_root text`.
- `graph_project text not null`.
- `status text not null`.
- `active_pin_id uuid`.
- `active_generation_id uuid`.
- `next_pass_number integer not null`.
- `disabled_at timestamp`.
- `inserted_at timestamp not null`.
- `updated_at timestamp not null`.

Constraints:

- Unique slug.
- Unique graph project when exclusivity is configured.
- Status check constraint.

### `repository_pins`

Purpose: immutable source and graph identity observations.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `root text not null`.
- `branch text`.
- `commit_sha text not null`.
- `dirty boolean`.
- `graph_generation text`.
- `graph_mode text`.
- `graph_node_count bigint`.
- `graph_edge_count bigint`.
- `coverage_digest text`.
- `observed_at timestamp not null`.

Constraints:

- Unique repository, root, branch, commit, graph generation.

### `runs`

Purpose: durable learning attempts.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `pin_id uuid not null`.
- `pass_number integer not null`.
- `state text not null`.
- `outcome text`.
- `lease_epoch bigint`.
- `current_gate text`.
- `selected_subsystem_id uuid`.
- `learning_note_id uuid`.
- `artifact_set_id uuid`.
- `cancel_requested boolean not null default false`.
- `cancel_requested_at timestamp`.
- `started_at timestamp`.
- `finished_at timestamp`.
- `blocked_reason text`.
- `failure_class text`.
- `failure_digest text`.
- `inserted_at timestamp not null`.
- `updated_at timestamp not null`.

Constraints:

- Unique repository and pass number.
- State check constraint.
- Outcome check constraint.
- Terminal timestamp consistency.

### `run_transitions`

Purpose: append-only state audit.

Fields:

- `id bigserial primary key`.
- `run_id uuid not null`.
- `from_state text`.
- `to_state text not null`.
- `event text not null`.
- `lease_epoch bigint`.
- `metadata jsonb not null`.
- `occurred_at timestamp not null`.

Constraints:

- Transition sequence is monotonic per run.

### `leases`

Purpose: fenced repository ownership.

Fields:

- `repository_id uuid primary key`.
- `run_id uuid not null`.
- `holder_id text not null`.
- `epoch bigint not null`.
- `claimed_at timestamp not null`.
- `renewed_at timestamp not null`.
- `expires_at timestamp not null`.
- `released_at timestamp`.
- `release_outcome text`.

Constraints:

- One current row per repository.
- Epoch positive.
- Expiry after renewal.

### `gates`

Purpose: seven-gate and publication results.

Fields:

- `id uuid primary key`.
- `run_id uuid not null`.
- `name text not null`.
- `state text not null`.
- `attempt integer not null`.
- `started_at timestamp`.
- `finished_at timestamp`.
- `summary text`.
- `input_digest text`.
- `result_digest text`.

Constraints:

- Unique run, gate name, attempt.

### `learning_notes`

Purpose: durable note-first artifact.

Fields:

- `id uuid primary key`.
- `run_id uuid not null unique`.
- `repository_id uuid not null`.
- `pin_id uuid not null`.
- `content text not null`.
- `content_digest text not null`.
- `schema_version integer not null`.
- `status text not null`.
- `file_path text`.
- `file_digest text`.
- `committed_at timestamp not null`.

Constraints:

- One note per run.
- Unique content digest per run.
- Published status requires file path and file digest when file output is enabled.

### `inventory_items`

Purpose: bounded repository coverage inventory.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `pin_id uuid not null`.
- `kind text not null`.
- `stable_key text not null`.
- `display_name text not null`.
- `source_path text`.
- `source_symbol text`.
- `discovery_state text not null`.
- `adjudication_state text`.
- `reason_code text`.
- `parent_id uuid`.
- `created_by_evidence_id uuid`.
- `updated_at timestamp not null`.

Constraints:

- Unique repository, pin, stable key.
- Adjudication state check.
- Reason required for omitted or blocked.

### `inventory_edges`

Purpose: inventory relationships.

Fields:

- `id uuid primary key`.
- `from_item_id uuid not null`.
- `to_item_id uuid not null`.
- `kind text not null`.
- `authority_class text not null`.
- `evidence_id uuid not null`.

Constraints:

- Unique from, to, kind, evidence.

### `claims`

Purpose: bounded behavioral statements.

Fields:

- `id uuid primary key`.
- `seam_id uuid not null`.
- `statement text not null`.
- `boundary text not null`.
- `authority_state text not null`.
- `source_path text not null`.
- `source_symbol text`.
- `start_line integer`.
- `end_line integer`.
- `source_digest text`.
- `stale_at timestamp`.

Constraints:

- Line range ordering.
- Publishable authority requirement checked by application and validator.

### `evidence`

Purpose: immutable observations.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `run_id uuid not null`.
- `pin_id uuid not null`.
- `kind text not null`.
- `authority_class text not null`.
- `operation text not null`.
- `arguments jsonb not null`.
- `request_digest text`.
- `response_digest text not null`.
- `body text`.
- `blob_ref text`.
- `coverage_caveat text`.
- `redaction_state text not null`.
- `observed_at timestamp not null`.

Constraints:

- Body or blob reference required.
- Authority class check.

### `claim_evidence`

Purpose: many-to-many evidence binding.

Fields:

- `claim_id uuid not null`.
- `evidence_id uuid not null`.
- `role text not null`.

Constraints:

- Composite primary key.

### `tool_invocations`

Purpose: durable agent action ledger.

Fields:

- `id uuid primary key`.
- `run_id uuid not null`.
- `turn_id uuid not null`.
- `tool_call_id text not null`.
- `tool_name text not null`.
- `arguments jsonb not null`.
- `policy_decision text not null`.
- `policy_reason text`.
- `state text not null`.
- `started_at timestamp`.
- `finished_at timestamp`.
- `result_evidence_id uuid`.

Constraints:

- Unique run and tool call ID.
- Accepted executions require allowed policy decision.

### `model_turns`

Purpose: provider request and response ledger.

Fields:

- `id uuid primary key`.
- `run_id uuid not null`.
- `turn_number integer not null`.
- `provider text not null`.
- `model text not null`.
- `request_digest text not null`.
- `response_digest text`.
- `stop_reason text`.
- `input_tokens bigint`.
- `output_tokens bigint`.
- `estimated_cost_minor bigint`.
- `state text not null`.
- `started_at timestamp not null`.
- `finished_at timestamp`.

Constraints:

- Unique run and turn number.

### `artifact_sets`

Purpose: complete proposed skill generations.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `run_id uuid not null unique`.
- `learning_note_id uuid not null`.
- `generation integer not null`.
- `manifest_digest text not null`.
- `state text not null`.
- `staging_path text not null`.
- `active_path text`.
- `template_version text not null`.
- `validated_at timestamp`.
- `activated_at timestamp`.

Constraints:

- Unique repository and generation.
- Unique manifest digest per repository.
- Learning note foreign key is not nullable.

### `artifacts`

Purpose: files within a generation.

Fields:

- `id uuid primary key`.
- `artifact_set_id uuid not null`.
- `relative_path text not null`.
- `kind text not null`.
- `content_digest text not null`.
- `byte_size bigint not null`.
- `source_seam_id uuid`.
- `content text`.
- `blob_ref text`.

Constraints:

- Unique artifact set and relative path.
- Content or blob reference required.

### `validation_results`

Purpose: deterministic checks.

Fields:

- `id uuid primary key`.
- `artifact_set_id uuid not null`.
- `check_name text not null`.
- `state text not null`.
- `details jsonb not null`.
- `input_digest text not null`.
- `observed_at timestamp not null`.

Constraints:

- Unique artifact set, check name, input digest.

### `publication_journals`

Purpose: recover filesystem activation.

Fields:

- `id uuid primary key`.
- `artifact_set_id uuid not null unique`.
- `strategy text not null`.
- `state text not null`.
- `destination_path text not null`.
- `staging_path text not null`.
- `backup_path text`.
- `expected_manifest_digest text not null`.
- `observed_destination_digest text`.
- `started_at timestamp`.
- `finished_at timestamp`.
- `error text`.

### `outbox_events`

Purpose: durable external publication intents.

Fields:

- `id uuid primary key`.
- `idempotency_key text not null unique`.
- `aggregate_type text not null`.
- `aggregate_id uuid not null`.
- `event_type text not null`.
- `destination text not null`.
- `payload jsonb not null`.
- `state text not null`.
- `attempt_count integer not null`.
- `available_at timestamp not null`.
- `claimed_by text`.
- `claim_expires_at timestamp`.
- `delivered_at timestamp`.
- `remote_ref text`.
- `last_error text`.

### `openviking_resources`

Purpose: map local artifacts to remote resources.

Fields:

- `id uuid primary key`.
- `outbox_event_id uuid not null`.
- `repository_id uuid not null`.
- `pass_number integer not null`.
- `local_digest text not null`.
- `target_uri text not null`.
- `remote_ref text`.
- `verification_query text`.
- `verification_state text not null`.
- `verified_at timestamp`.

Constraints:

- Unique target URI and local digest.

### `blockers`

Purpose: durable impediments.

Fields:

- `id uuid primary key`.
- `repository_id uuid not null`.
- `run_id uuid`.
- `inventory_item_id uuid`.
- `kind text not null`.
- `summary text not null`.
- `details jsonb not null`.
- `state text not null`.
- `opened_at timestamp not null`.
- `resolved_at timestamp`.
- `resolution_evidence_id uuid`.

## 5. Transaction boundaries

### Repository registration transaction

Insert repository.

Insert initial target pin when known.

Insert audit transition.

### Run creation transaction

Lock repository row.

Allocate pass number.

Insert queued run.

Increment next pass number.

Insert transition.

### Lease claim transaction

Select eligible run.

Claim or replace expired repository lease.

Increment lease epoch.

Transition run to claimed.

Commit before starting worker.

### Learning-note transaction

Insert immutable note.

Update run with note ID.

Transition run to note-published intent only after file materialization policy succeeds.

### Artifact result transaction

Insert artifact set and file records.

Insert validation results.

Record publication intent.

Do not mark active before filesystem activation succeeds.

### Pass completion transaction

Verify lease epoch.

Update inventory adjudications.

Update next targets.

Record active artifact generation.

Insert OpenViking outbox events.

Transition run terminal.

Release lease.

## 6. Note-first publication

The learning note has two durable representations.

SQL stores canonical content and digest.

The work-record volume stores Markdown for operators and future agents.

### Note publication sequence

1. Model proposes note content.
2. Runtime validates required sections.
3. SQL transaction inserts note with `status = staged`.
4. Runtime writes a temporary note file on the destination filesystem.
5. Runtime flushes and closes the file.
6. Runtime renames the temporary file to the canonical pass-note path.
7. Runtime reads back and hashes the canonical file.
8. SQL transaction records file path and digest.
9. SQL transaction sets note status to `published`.
10. Run transitions to `note_published`.

### Crash recovery

If SQL staged but no file exists, rewrite from canonical SQL content.

If file exists but SQL lacks digest, hash and reconcile exact content.

If content differs, preserve both and block publication.

Never overwrite an unexplained conflicting note.

## 7. Artifact generation model

Every run synthesizes a complete target leaf generation.

A generation contains:

- `SKILL.md`.
- Existing retained references.
- New or rewritten references.
- Manifest metadata outside the leaf when required.

The generation is content-addressed.

The active leaf never contains half of a generation by design intent.

## 8. Staging layout

Proposed state volume layout:

```text
/state/
├── notes/<repository>/<pass>/research.md
├── generations/<repository>/<generation>/tree/
├── manifests/<repository>/<generation>.json
├── journals/<artifact-set-id>.json
├── backups/<repository>/<generation>/
└── blobs/sha256/<prefix>/<digest>
```

Proposed skill volume target:

```text
/agents/skills/<leaf>/
```

Repository source volume:

```text
/sources/<repository>/
```

Source volume is read-only.

State and skill volumes are read-write.

## 9. Artifact validation

Before activation, validate:

- Expected file set.
- UTF-8 encoding.
- No symlink escapes.
- No unexpected executable files.
- `SKILL.md` frontmatter.
- Loader entry syntax.
- Capsule map syntax.
- Capsule-v2 marker.
- Required capsule headings.
- Source field.
- Path and symbol field.
- Signature field.
- Data shape field.
- Decisive source section.
- Flow field.
- Invariant field.
- Probe field.
- Retrieve section.
- Verdict section.
- Loader-map-disk bidirectional parity.
- Unique capsule basenames.
- Evidence binding for every capsule.
- Template version.
- Maximum file sizes.
- No target-source content beyond allowed excerpt bounds.

## 10. Activation strategies

### Strategy A: generation directory and symlink swap

Write immutable generations outside the catalog path.

Point `/agents/skills/<leaf>` to the active generation.

Activate with atomic symlink rename.

Advantages:

- Atomic reader view.
- Fast rollback.
- Immutable history.

Risks:

- Skill hosts may reject or resolve symlinks differently.
- Mounted volume policies may disallow symlinks.

Status: preferred after capability probe.

### Strategy B: journaled directory replacement

Rename current leaf to backup.

Rename staged generation into the leaf path.

Verify destination digest.

Remove backup after commit.

Advantages:

- Plain directory output.
- Compatible with hosts that reject symlinks.

Risks:

- Two-rename window.
- Readers may observe a missing path briefly.

Mitigation:

- Publication lock.
- Recovery journal.
- Very short activation window.
- Optional host maintenance signal.

### Strategy C: file-by-file atomic rename

Write each file to a sibling temporary path.

Rename files individually.

Advantages:

- Simple filesystem primitives.

Risks:

- Readers can observe parity mismatch.
- Rollback is complex.

Status: reject for multi-file generations.

## 11. Publication journal states

- `prepared`.
- `old_backed_up`.
- `new_activated`.
- `verified`.
- `committed`.
- `rollback_started`.
- `rolled_back`.
- `conflicted`.

### Journal invariants

A journal exists before the first destination rename.

Every transition is flushed before the next rename.

The expected manifest digest is immutable.

A stale lease epoch cannot advance a journal.

Recovery may continue or roll back, never guess silently.

## 12. Artifact activation sequence

1. Acquire repository publication lock.
2. Verify active lease epoch.
3. Revalidate artifact set.
4. Write `prepared` journal.
5. Verify staging and destination share required filesystem semantics.
6. Activate using configured strategy.
7. Read destination manifest.
8. Recompute destination digest.
9. Mark journal `verified`.
10. SQL transaction marks artifact set active.
11. SQL transaction updates repository active generation.
12. SQL transaction inserts OpenViking outbox events.
13. Mark journal `committed`.
14. Release publication lock.
15. Clean backups asynchronously after retention period.

## 13. Recovery reconciliation

Recovery runs before scheduler admission.

### Run recovery

Find nonterminal runs without live workers.

Inspect lease expiry and epoch.

Mark expired executing runs orphaned.

Classify resumable state.

Requeue only states with no uncertain side effect.

Reconcile publication states before requeue.

### Note recovery

Reconcile staged note rows and files.

### Artifact recovery

Read every nonterminal publication journal.

Compare staging, destination, and backup digests.

Continue activation when state is unambiguous.

Roll back when destination is absent and backup is valid.

Block when multiple conflicting valid trees exist.

### Outbox recovery

Release expired event claims.

Do not duplicate delivered events with matching remote refs.

Retry pending events according to policy.

## 14. OpenViking role

OpenViking is a searchable copy of learning outputs.

OpenViking does not select the next repository.

OpenViking does not own pass numbers.

OpenViking does not determine closure.

OpenViking hits are pointers, not behavioral proof.

The local database and artifact catalog remain authoritative.

## 15. OpenViking resource naming

Use stable per-pass roots:

```text
viking://resources/llm-repo-learning-pass<pass>-<repository>/
```

Proposed child resources:

- `research.md`.
- `verification.md`.
- `state.md` when configured.
- `references/<capsule>.md`.
- `SKILL.md` when configured.
- `manifest.json` when supported.

The target naming convention matches the existing workflow.

## 16. Outbox event types

- `openviking.add_learning_note`.
- `openviking.add_verification_record`.
- `openviking.add_capsule`.
- `openviking.add_skill_leaf`.
- `openviking.verify_symbol`.

Each event has a deterministic idempotency key.

Each event carries local content digest.

Payloads reference blobs rather than duplicating large bodies when practical.

## 17. Outbox state machine

- `pending`.
- `claimed`.
- `delivering`.
- `delivered`.
- `verifying`.
- `verified`.
- `retry_wait`.
- `failed_permanent`.

### Claim behavior

Workers claim with skip-locked semantics when PostgreSQL is used.

Claims expire.

Claim ownership includes publisher instance ID.

A stale publisher cannot mark an event delivered.

### Delivery behavior

Reconcile existing target URI when possible.

Send with idempotency key when supported.

Record remote reference.

Do not delete or overwrite unrelated resources.

### Verification behavior

Select one newly cited stable symbol.

Run semantic find scoped to the pass root.

Read the hit when available.

Verify that the expected local digest or decisive text is represented.

Record success or degraded failure.

## 18. OpenViking failure policy

### Transient failures

- Connection timeout.
- Temporary unavailability.
- Rate limit.
- Queue still processing.

Retry with bounded backoff.

### Permanent failures

- Invalid target URI.
- Authentication denied.
- Unsupported payload.
- Policy rejection.

Record permanent failure and alert.

### Core pass effect

Local artifact completion remains valid.

Repository status records `openviking_degraded`.

Operators can replay the outbox after repair.

## 19. OpenViking transport abstraction

```elixir
defmodule LearningAgent.OpenViking.Client do
  @callback add(OpenViking.Resource.t(), keyword()) ::
    {:ok, OpenViking.RemoteRef.t()} |
    {:error, OpenViking.Error.t()}

  @callback find(String.t(), String.t(), keyword()) ::
    {:ok, [OpenViking.Hit.t()]} |
    {:error, OpenViking.Error.t()}

  @callback read(String.t(), keyword()) ::
    {:ok, OpenViking.Document.t()} |
    {:error, OpenViking.Error.t()}
end
```

Candidate implementations:

- Native HTTP API adapter.
- MCP adapter when exposed.
- Development host proxy.

The installed `ov` CLI is not assumed inside production containers.

## 20. Idempotency keys

### Note file key

`note:<repository-id>:<pass>:<content-digest>`.

### Artifact generation key

`artifact:<repository-id>:<manifest-digest>`.

### OpenViking add key

`ov:add:<target-uri>:<content-digest>`.

### OpenViking verify key

`ov:verify:<target-uri>:<query-digest>:<content-digest>`.

### Tool invocation key

`tool:<run-id>:<tool-call-id>`.

### Model turn key

`turn:<run-id>:<turn-number>`.

## 21. Content addressing

Use SHA-256 for artifact and evidence digests.

Canonicalize JSON before hashing.

Normalize line endings for generated Markdown before hashing.

Do not normalize decisive source excerpts before hashing source evidence.

Store hash algorithm with each digest for future migration.

## 22. Retention

Retain all learning notes by default.

Retain all published capsule generations by default.

Retain failed staging trees for a bounded forensic period.

Retain publication journals indefinitely or until archived.

Retain provider prompt bodies according to security policy.

Retain aggregate usage indefinitely.

Retention policy is operator configurable.

Deletion is never model initiated.

## 23. Backup and restore

Back up SQL and skill volumes consistently.

A database backup without matching active artifacts is incomplete.

A skill-volume backup without manifests is incomplete.

Restore procedure:

1. Stop scheduler admission.
2. Restore SQL.
3. Restore state and skill volumes.
4. Run publication reconciliation.
5. Recompute active manifest digests.
6. Mark mismatches blocked.
7. Resume scheduler only after readiness.

## 24. Migration strategy

Migrations are ordered and immutable after release.

A release checks required schema version.

Destructive migrations require explicit operator mode.

Artifact template migrations do not silently rewrite old generations.

A new template version creates new artifact generations during revalidation.

## 25. Data protection

Encrypt transport to SQL when remote.

Encrypt provider and MCP credentials at the orchestration secret layer.

Do not store credentials in evidence arguments.

Redact authorization headers before persistence.

Consider column encryption for full prompt bodies.

Use separate database roles for migration and runtime when operationally available.

## 26. Database observability

Track:

- Query latency.
- Transaction retries.
- Connection-pool saturation.
- Lease claim conflicts.
- Stale epoch rejections.
- Outbox backlog.
- Orphaned run count.
- Publication journal backlog.
- Artifact digest conflicts.
- Migration version.

## 27. Storage acceptance criteria

- Duplicate run creation cannot reuse a pass number.
- Duplicate tool delivery cannot execute twice.
- Cancel-before-start survives worker registration.
- An artifact set without a note is rejected.
- A stale lease epoch cannot commit.
- A crash after note SQL insert recovers the note file.
- A crash during artifact activation recovers or blocks deterministically.
- A crash after outbox insertion preserves delivery intent.
- Duplicate OpenViking delivery does not create uncontrolled twins.
- OpenViking downtime does not lose local artifacts.
- Closure can be recomputed from SQL and evidence digests.
- Active generation always points to a verified manifest.

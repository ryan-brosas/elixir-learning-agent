# Event-Sourced Foundation Projection

## Purpose

The automatic learning path builds one stable foundation for a pinned repository. It does not append pass prose to an ever-growing note and it does not generate procedures.

The data flow is:

```text
repository pin
  -> immutable pass observation
  -> zero or more accepted seam capsules
  -> complete <slug>-foundation projection
```

PostgreSQL owns the durable facts. The filesystem foundation is a derived, content-addressed view that can be rebuilt from those facts.

## Durable facts

### Repository pin

Every observation, accepted capsule, and projection generation is scoped to one `repository_pins.id`. Evidence from another pin is stale for the current projection and is never included, even when it belongs to the same repository.

### Pass observation

`pass_observations` stores one immutable work record per run:

- repository, run, pass, and pin identity;
- bounded source paths and direct evidence;
- the model identity, when a model participated;
- coverage, unresolved questions, and omissions;
- observation time.

The context exposes insert/idempotent-replay behavior, not update behavior. A pass may observe no acceptable reusable seam.

Published `learning_notes` remain causal work records for note-first crash recovery. Their full bodies are not the memory input for later passes.

### Accepted seam capsule

`foundation_capsules` stores an immutable accepted seam at one pin. Its stable key is derived from the seam boundary rather than the pass number. Each capsule binds:

- a direct source excerpt, SHA-256 digest, and source revision;
- test evidence, or an explicit test caveat;
- a precise question and boundary;
- an invariant and explicit limits.

Replaying the same fact is idempotent. Reusing the same stable key with different content is a conflict, not an overwrite.

## Bounded prior context

A later pass receives only a bounded current-pin projection of:

- accepted seam identity, source path, question, and invariant;
- covered source paths;
- unresolved items;
- omissions.

The context has item and byte bounds. It never injects complete recent learning-note bodies. This avoids cumulative-note growth and prevents evidence from an old pin entering a new pass.

## Complete projection

Every successful pass renders the complete set of accepted capsules for its active pin. It does not render only the newest pass delta. Therefore:

- a zero-capsule pass is valid;
- a pass may leave the foundation byte-for-byte unchanged;
- every valid prior capsule at the same pin remains present;
- capsules from other pins are absent;
- stable capsule filenames do not contain pass numbers.

The active path is always:

```text
<skills-root>/<slug>-foundation/
```

A generation is staged and verified, installed under a content-addressed immutable directory, journaled, and atomically activated. The journal intent precedes the active-link mutation. The artifact result, repository/run links, and idempotent OpenViking materialization intent commit in one database transaction; the outbox points at the immutable generation rather than the mutable active link. If its manifest is already active, the run links to that projection without creating a second filesystem view. Startup recovery replays staged projection activation.

## Generated contract

`SKILL.md` is a manual, model-disabled foundation index. Its YAML-safe frontmatter includes:

```yaml
kind: foundation
invocation: manual
disable-model-invocation: true
producer: elixir-learning-agent
projection-version: 1
```

The loader and capsule map enumerate every `references/<stable-key>.md` file. Loader/map/disk parity and the manifest digest cover the complete generation.

## Procedure promotion boundary

Automatic execution can create observations, accept directly evidenced foundation capsules, and activate foundation projections only. The projection validator rejects non-foundation output, and the publisher requires the learning-agent ownership marker before replacing a managed projection.

A future procedure must be created through a separate explicit operator promotion boundary with its own review and provenance. No such automatic promotion path exists today. Existing unmanaged or human-authored leaves are preserved and cause a conflict rather than being overwritten.

## Operator terminology

Operator API and activity surfaces call the derived artifact a **foundation projection**. API projection identifiers are aliases over the existing artifact-set storage identity so the persistent compatibility columns need not be rewritten. A learning note is described as a **work record**, not as accumulated repository memory.

# User Profile

## Identity

- **Name:** `[NEEDS CLARIFICATION: user has not supplied a preferred name]`
- **Role:** Project owner/operator for the Elixir Learning Agent.
- **Git contributor identity:** `ryan-brosas` GitHub owner for this repository — Evidence: authenticated `gh repo view`.

## Communication Preferences

- **Detail level:** Concise, with concrete files, commands, and verification results.
- **Style:** Prefer evidence-backed implementation, template consistency, and using available MCP/IDE integrations rather than assuming they work.
- **Example of preferred answer shape:** The current request explicitly asked for a deep init using the repository/template/CI contracts and for MCP/IDE tooling to be utilized.

## Approval Boundaries

Ask before:

- destructive filesystem or database operations;
- committing, pushing, force-pushing, or opening/merging a pull request unless the user explicitly requests that action;
- enabling live provider, MCP, or OpenViking credentials in deployment configuration.

Auto-approve:

- read-only discovery and scoped implementation/verification for the active request.

## Git Workflow

- **Commit mode:** Ask first unless the user has explicitly requested a commit in the current request.
- **Staging rule:** Stage only files changed for the active request; preserve unrelated work.
- **Commit style:** Conventional `type(scope): summary` subjects, enforced for PR titles by `.github/workflows/pr-title.yml`.
- **Push / PR policy:** Explicit request required; default branch is `main`; current working branch is `fix/inspection-runtime-hardening`.
- **Protection rules:** Never force-push or bypass checks; do not rewrite shared history.

## Workflow Preferences

- **Starting non-trivial work:** Read repository source and the applicable templates; use MCP/IDE capabilities only after verifying registration and coverage.
- **Change size:** Scope changes to the agreed request; avoid drive-by runtime refactors.
- **Dirty repositories:** Preserve pre-existing and concurrent changes; inspect status before staging.
- **Navigation:** Prefer semantic/IDE/MCP navigation when available, then verify against local source.
- **Verification:** Run the canonical gate and direct behavioral probes before completion claims.

## Technical Preferences

- Elixir/OTP modular architecture, durable state, explicit boundaries, and conservative completion claims — Evidence: `DESIGN.md` and existing implementation.
- Template-driven README, agent, state, and CI artifacts — Evidence: current initialization request.
- Host-side MCP and JetBrains IDE inspection usage without turning host tools into runtime dependencies — Evidence: `.idea/mcp-steroid.md`, `inspections/`, and current request.

## Things to Remember

1. Use the repository templates and maintain cross-file consistency.
2. Treat source/tests and executed gates as stronger evidence than inspection or model claims.
3. Ask before irreversible Git/GitHub actions unless explicitly authorized.

## Unknowns

- Preferred user name and public attribution — `[NEEDS CLARIFICATION: not supplied]`.
- License and redistribution policy — `[NEEDS CLARIFICATION: GitHub metadata has no license]`.
- Default live provider/MCP/OpenViking environment and budget — `[NEEDS CLARIFICATION: deployment decision pending]`.

---

_Update this file when the user states a durable preference._
_Do not store secrets, transient task details, or speculative personal information._

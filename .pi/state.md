# State

## Current Position

**Date:** 2026-08-29
**Project:** Elixir Learning Agent
**Phase:** Deep initialization and CI bootstrap
**Status:** Review
**Active focus:** Deep-init artifacts and GitHub quality automation are written; post-write verification is green and the scoped diff is ready for review.
**Primary success criterion:** Durable, evidence-backed learning passes with a green deterministic safety core.
**Primary users:** Repository-learning operators and agent/IDE workflows.
**Tracker:** GitHub issues enabled; no issue ID is assigned to this initialization.

## Current Repository Condition

- Branch: `fix/inspection-runtime-hardening`, tracking `origin/fix/inspection-runtime-hardening`; default branch is `main`.
- Remote: `https://github.com/ryan-brosas/elixir-learning-agent.git`; GitHub repository is private, issues/projects/wiki are enabled, and no license metadata is set.
- Before this init write, the branch had the implementation commits `79e5744` and `2cd36f2` and no working-tree changes. This init adds the files listed in the session handoff; preserve any unrelated changes.
- Environment: Elixir 1.20.3 / OTP 29, Mix 1.20.3, Docker 29.7.2, Compose 5.5.0, GitHub CLI 2.98.0, IntelliJ IDEA 2026.2.1 through MCP Steroid.

## Verification State

| Gate | Command | Last result | Date |
|---|---|---|---|
| Compose syntax | `docker compose config --quiet` | pass | 2026-08-29 |
| Format | `mix format --check-formatted` | pass | 2026-08-29 |
| Strict compile | `mix compile --warnings-as-errors` | pass | 2026-08-29 |
| Tests | `mix test` | pass; 112 passed | 2026-08-29 |
| Release | `MIX_ENV=prod mix release --overwrite` | pass; release assembled | 2026-08-29 |
| Docker image | `docker build --pull --tag learning-agent:ci .` | pass; production image built | 2026-08-29 |
| Compose runtime | `docker compose up --build -d` | not run locally; readiness probe remains pending | 2026-08-29 |
| Dockerfile syntax | `docker build --check .` | pass; no warnings | 2026-08-29 |
| Qodana | `.github/workflows/qodana.yml` | configured; not run locally | 2026-08-29 |
| Codebase Memory graph | `index_status` | pass; project `learning-agent` ready, 1418 nodes/2109 edges; `Dockerfile:31` parse-partial caveat | 2026-08-29 |
| JetBrains MCP | `steroid_list_projects`, `steroid_list_windows` | pass; project open/indexed | 2026-08-29 |
| OpenViking | `find` + `read` | pass; prior-art hit returned and a URI was read | 2026-08-29 |

**Pending checks:** GitHub Actions must prove the hosted Beam/database/container contract; Qodana remains token-gated and supplementary. Full Compose readiness is still not locally run. Re-index the active repository only when the graph is stale or explicitly requested.

## Recent Completed Work

| Work | Title | Completed | Evidence |
|---|---|---|---|
| prior | Deterministic learning runtime foundation | 2026-08-29 | `docs/06-implementation-roadmap.md`; current 112-test suite |
| prior | Inspection/release hardening | 2026-08-29 | commit `79e5744`; `qodana.yaml`, `Dockerfile`, `bin/server` |
| init | Deep project initialization and CI bootstrap | 2026-08-29 | template-based artifact set; canonical gate, YAML, text, and Dockerfile checks pass |

## Active Decisions

| Date | Decision | Rationale | Impact | Evidence |
|---|---|---|---|---|
| 2026-08-29 | Use canonical templates for project spine, README, PR/issues, and CI | keeps agent/maintainer entrypoints consistent with the host template contract | creates `AGENTS.md`, `.pi/*`, README, `.github/*` | `/home/utopia/.agents/templates/*` |
| 2026-08-29 | Keep Qodana token-gated and supplementary | inspection exports and Qodana are useful but must not replace executable gates | no secret is required for normal CI quality | `qodana.yaml`, `.github/workflows/qodana.yml` |
| 2026-08-29 | Treat active Codebase Memory indexing as an explicit follow-up | live probe reported the repository is not indexed | no graph claims are made for this checkout | MCP `index_status` output |

## Blockers

| Work | Blocker | Since | Owner | Unblock path |
|---|---|---|---|---|
| Full Compose acceptance | Service startup/readiness has not been probed in this session | 2026-08-29 | deployment environment | run `docker compose up --build -d` and check both health endpoints |
| Live external learning | Production MCP/provider/OpenViking endpoints and budgets are not recorded | 2026-08-29 | project operator | select credentials, endpoints, models, and cost limits |

## Open Questions

| Question | Context | Blocking | Priority |
|---|---|---|---|
| What license should be selected? | GitHub `licenseInfo` is null | No for private development; yes for redistribution | Medium |
| What production MCP/provider/OpenViking configuration is used? | adapter seams are present, deployment contract is absent | Yes for live learning | High |
| When should the active Codebase Memory project be re-indexed? | Current project `learning-agent` is ready; `Dockerfile:31` is parse-partial | No for local gates | Medium |

## Context Notes

### Technical

- `LearningAgent.Application` starts recovery after the supervisor tree is up; test config disables scheduler/renewer background loops.
- The Plug API is implemented; the LiveView frontend remains a design milestone.
- Qodana excludes generated/vendor paths and local `.pi` state; exported inspection XML remains ignored.

### Product

- The product claims evidence-backed reusable behavior, not total subjective comprehension.
- The repository is private and no redistribution license has been selected.

### Process

- `AGENTS.md` is the short operating spine; `.pi/project.md` and `.pi/tech-stack.md` hold on-demand detail.
- Context probes used Codebase Memory (`learning-agent`, ready, 1418 nodes/2109 edges, one parse-partial Dockerfile range), OpenViking retrieval/read, JetBrains MCP Steroid, local source, GitHub metadata, and real project commands. Missing/unavailable sources are recorded rather than assumed.

## Next Actions

1. [x] Run the post-init canonical completion command and inspect all results.
2. [x] Parse/check all GitHub workflow YAML, scan generated text, and review `git diff --check`.
3. [ ] Review/stage this scoped diff; commit, push, or open a PR only when explicitly requested.
4. [ ] Define live external credentials/budgets before autonomous turns; re-index only if the active graph becomes stale.

## Session Handoff

**Last Session:** 2026-08-29
**Next Session Priority:** Review the CI repair and hosted checks; then commit/push only with explicit approval.
**Known Issues:** Full Docker Compose readiness and Qodana are not locally run; Codebase Memory has a parse-partial caveat for `Dockerfile:31`.
**Read first:** `AGENTS.md`, `.pi/project.md`, `.pi/tech-stack.md`, `.pi/roadmap.md`, `docs/06-implementation-roadmap.md`.
**Context Links:** `DESIGN.md`, `README.md`, `.github/workflows/pr-quality.yml`, `.github/workflows/qodana.yml`, `https://github.com/ryan-brosas/elixir-learning-agent`.

---

_Update this file at the end of each significant session or when state changes._
_This file is the "you are here" marker for the project. Keep observed facts separate from planned work; mark unverified claims `[NEEDS CLARIFICATION: reason]`._

# Tech Stack

This is the detected stack for the checkout. Project dependencies are separated from host-side tools; every command below was probed before this initialization.

## Framework & Language

- **Framework:** OTP application with Ecto SQL and Plug Cowboy; Phoenix LiveView is designed but not yet present — Evidence: `mix.exs:16-20`, `lib/learning_agent/application.ex:15-43`, `lib/learning_agent_web/router.ex:1-9`, `docs/07-frontend-control-plane.md`.
- **Language:** Elixir `~> 1.20` — Evidence: `mix.exs:4-8`.
- **Runtime:** Local probe: Elixir 1.20.3 on Erlang/OTP 29; Dockerfile pins the build/runtime image to Elixir 1.20.4 on OTP 29.0.5 — Evidence: `elixir --version`, `Dockerfile:7-18`.
- **Project manifest:** `mix.exs` with `mix.lock` — Evidence: repository root.

## Project Dependencies vs Host Tools

- **Project dependencies:** `ecto_sql ~> 3.12` (locked 3.14.0), `postgrex ~> 0.19` (locked 0.22.4), `jason ~> 1.4` (locked 1.4.5), `plug_cowboy ~> 2.7` (locked 2.9.0), and test-only `stream_data ~> 1.0`; transitive `ecto 3.14.2`, Plug 1.20.3, Cowboy 2.18.0, and Telemetry 1.4.2 — Evidence: `mix.exs:36-44`, `mix deps`.
- **Host tools:**

  | Tool | Version | Evidence | Used by the project? |
  |---|---|---|---|
  | Elixir | 1.20.3 | `elixir --version` | yes, runtime/compiler |
  | Erlang/OTP | 29 | `elixir --version` | yes, runtime |
  | Mix | 1.20.3 | `mix --version` | yes, build/test/release |
  | Docker | 29.7.2 | `docker --version` | yes, deployment verification |
  | Docker Compose | 5.5.0 | `docker compose version` | yes, deployment topology |
  | GitHub CLI | 2.98.0 | `gh --version` | operator/CI setup, not runtime |
  | IntelliJ IDEA | 2026.2.1 | JetBrains MCP Steroid listing | host IDE, not runtime |
  | Qodana | configured, execution not run locally | `qodana.yaml`, `.github/workflows/qodana.yml` | host quality tool |

## Styling & UI

- **CSS:** None.
- **Components:** None.
- **Design System:** None. The current HTTP surface is JSON/Plug; LiveView is planned.

## Data & State

- **Database:** PostgreSQL 16 — Evidence: `docker-compose.yml:2-14`, `docs/06-implementation-roadmap.md` milestone 2.
- **ORM:** Ecto SQL/Postgrex — Evidence: `mix.exs:40-41`, `lib/learning_agent/repo.ex`.
- **State Management:** Durable SQL contexts plus OTP supervision; no client state library — Evidence: `lib/learning_agent/*_context.ex`, `lib/learning_agent/application.ex`.
- **API Style:** Plug JSON HTTP API with public health and role-gated `/v1/*` routes — Evidence: `lib/learning_agent_web/router.ex:13-104`.

## Commands

| Command | Status | Purpose | Verified |
|---|---|---|---|
| `mix deps.get` | works | install project dependencies | `mix deps` showed all locked dependencies available, 2026-08-29 |
| `mix ecto.migrate` | works | apply PostgreSQL schema migrations | `docs/06-implementation-roadmap.md` milestone 2; current test DB is migrated |
| `mix format --check-formatted` | works | enforce Elixir formatting | exit 0, 2026-08-29 |
| `mix compile --warnings-as-errors` | works | strict compile gate | exit 0, 2026-08-29 |
| `mix test` | works | ExUnit + PostgreSQL integration suite | exit 0, 113 passed, 2026-08-29 |
| `MIX_ENV=prod mix release --overwrite` | works | assemble OTP release | exit 0, release created, 2026-08-29 |
| `docker compose config --quiet` | works | validate service topology | exit 0, 2026-08-29 |
| `docker build --pull --tag learning-agent:ci .` | works | build the production image | exit 0, 2026-08-29 |
| `docker compose up --build -d` | not run locally | full container/readiness acceptance | image build passes; service startup/readiness still pending, 2026-08-29 |
| `mix lint` / typecheck | none | no separate lint/typecheck task is configured | no task in `mix.exs` |
| Qodana scan | configured, not run | IDE inspection quality gate | no local Qodana run |

## CI

- **Workflows:** `.github/workflows/pr-quality.yml` (Beam/test/release/container gate), `.github/workflows/pr-title.yml` (title grammar), `.github/workflows/qodana.yml` (optional token-gated IDE analysis), `.github/workflows/dependency-review.yml` (capability-gated pull-request dependency review) — Evidence: generated from this initialization.
- **Local reproduction:** `docker compose config --quiet && mix format --check-formatted && mix compile --warnings-as-errors && mix test && MIX_ENV=prod mix release --overwrite`; CI additionally uses a PostgreSQL service and builds the Docker image.

## Generated Files

- `_build/`, `deps/`, `cover/`, `doc/`, release output, and `.pi/fabric/` are generated/local state and ignored by `.gitignore`.
- Inspection XML files under `inspections/` are exported host diagnostics and are ignored from source control by `/inspections/`; Qodana reads project-owned source with generated/vendor paths excluded.
- Regenerate with `mix deps.get`, `mix release`, or the IDE inspection export as appropriate — verify with the canonical gate and `git diff --check`.

## Testing

- **Unit / integration:** ExUnit, Ecto SQL Sandbox, real PostgreSQL integration, TCP MCP stubs, and Plug.Test — Evidence: `test/` and `test/test_helper.exs`.
- **E2E:** No dedicated browser or full Compose E2E suite yet — Evidence: `docs/06` milestone 15 and `docs/07`.
- **Coverage Target:** None configured; do not infer coverage from pass count.
- **Coverage gaps:** Live external model/OpenViking transport, full container readiness, LiveView/browser flows, and fault-injection completeness remain open.

## Active Integrations

- PostgreSQL 16 via Ecto/Postgrex — Evidence: `config/config.exs`, `docker-compose.yml`.
- Codebase Memory MCP client and TCP framing seam — Evidence: `lib/learning_agent/mcp/`; host graph project `learning-agent` is ready with 1418 nodes/2109 edges and a parse-partial caveat at `Dockerfile:31`.
- OpenViking client/outbox behavior seam — Evidence: `lib/learning_agent/open_viking/`.
- OpenAI-compatible provider adapter seam — Evidence: `lib/learning_agent/providers/openai_compatible.ex`.
- JetBrains MCP Steroid / IntelliJ IDEA project integration — Evidence: `.idea/mcp-steroid.md` and live IDE tool listing.
- Qodana inspection configuration/exported inspections — Evidence: `qodana.yaml`, `inspections/`.

## Environments

- **test:** `MIX_ENV=test`, Ecto SQL Sandbox, database `learning_agent_test`, scheduler and lease-renewer disabled — Evidence: `config/config.exs`, `config/runtime.exs`, `test/test_helper.exs`.
- **local:** Mix release/dev process, host PostgreSQL default `127.0.0.1:5433`, HTTP port from `LA_HTTP_PORT` — Evidence: `config/config.exs`.
- **production/Compose:** release image, `postgres` service, internal port 5432, HTTP port 4000, migrations through `bin/server` — Evidence: `Dockerfile`, `docker-compose.yml`, `bin/server`.
- **Rollback:** artifact journal/backup exists; production database/image rollback procedure is `[NEEDS CLARIFICATION: deployment owner and backup policy are not recorded]`.

## Key Constraints

- Never mutate a studied source repository; source mounts are read-only.
- No arbitrary shell, package installation, source-write, or model-delegation tool is available to the learning runtime.
- Durable state and external intents must be persisted before side effects.
- OpenViking degradation must remain visible and must not erase local learning.
- Every negative or complete claim is bounded by pin and coverage evidence.
- Host MCP/IDE/Qodana tools are optional quality/navigation surfaces, never Mix dependencies or secrets.

## Unknowns

- Production MCP endpoint/credential provisioning — `[NEEDS CLARIFICATION: deployment contract not in checkout]`.
- Default provider model IDs, cost ceilings, and wall-time budgets — `[NEEDS CLARIFICATION: required before live autonomous turns]`.
- License selection — `[NEEDS CLARIFICATION: private repository has no license metadata]`.
- Minimum supported OTP patch level separate from the Docker image — `[NEEDS CLARIFICATION: only project Elixir constraint and image pin are recorded]`.

## Verification Commands

```bash
docker compose config --quiet
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix release --overwrite
```

---

_Update this file when tech stack or constraints change._
_AI will capture architecture, conventions, and gotchas in Pi session memory (`memory.recall`) as it works._

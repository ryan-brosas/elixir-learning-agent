<div align="center">

# Elixir Learning Agent

**A durable, evidence-backed repository-learning runtime built as an OTP application.**

It studies one pinned repository at a time, preserves learning notes and artifacts, and keeps safety, recovery, and honest completion at the center.

[![Project quality](https://github.com/ryan-brosas/elixir-learning-agent/actions/workflows/pr-quality.yml/badge.svg?branch=main)](https://github.com/ryan-brosas/elixir-learning-agent/actions/workflows/pr-quality.yml)
[![Elixir](https://img.shields.io/badge/Elixir-1.20-4B275F?logo=elixir)](https://elixir-lang.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://www.postgresql.org/)

</div>

## Run

The local test and release gates require Elixir 1.20+, a compatible Erlang/OTP runtime, and PostgreSQL reachable at the configured host and port. The checked-in defaults use `127.0.0.1:5433` for local development and `postgres:5432` inside the Compose network.

```bash
mix deps.get
mix ecto.migrate
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix release --overwrite
```

Validate the deployment configuration without starting services:

```bash
docker compose config --quiet
```

The default Compose stack builds the release image, starts PostgreSQL, runs migrations through `bin/server`, and exposes the operator API and model playground on port `4000`. Local Compose model dogfooding is loopback-bound and uses only the URL/API key entered in the browser; `.env` model values are optional defaults and no bearer token is needed for the model page.

```bash
cp .env.example .env
# Optional: set LA_OPERATOR_TOKEN to protect the non-model operator routes.
# The model URL, API key, and model can be entered in the browser instead.
docker compose up --build -d
xdg-open http://localhost:4000/
curl http://localhost:4000/health/live
curl http://localhost:4000/health/ready
```

The production container image now builds locally and in GitHub Actions. Full Compose startup/readiness remains a separate deployment probe.

## Why

Repository-learning automation needs more than retrieval. It needs durable run state, source and test evidence, bounded model capabilities, recoverable artifact publication, and a conservative definition of completion.

The current implementation already provides the deterministic core:

- PostgreSQL/Ecto persistence for repositories, runs, leases, notes, artifacts, and an outbox.
- Scheduler, supervised run workers, lease renewal, cancellation, and startup recovery.
- A framed Codebase Memory MCP client with request correlation and typed operations.
- Bounded source reads and a registered-tool firewall with no generic shell or source-write operation.
- Note-first Markdown publication with read-back hashing.
- Capsule-v2 rendering and loader/map/disk parity checks.
- Recoverable artifact generations and an OpenViking publication outbox seam.
- Role-gated JSON health and operator endpoints plus telemetry formatting.
- A responsive browser model playground at `/` with non-secret model status and an operator-only completion probe.
- A bounded OpenAI-compatible provider adapter with normalized responses and injectable test transport.

The full product design remains ahead of the implementation: LiveView operations, additional provider adapters, exhaustive multi-pass closure, and production OpenViking transport wiring are explicit follow-on work rather than hidden claims.

## How it fits

```text
operator / CI
      │
      ▼
Plug operator API ──► durable Ecto contexts ──► PostgreSQL
                              │
                              ├── Scheduler ──► RunSupervisor ──► RunWorker
                              │                                  │
                              │                                  ├── lease + recovery
                              │                                  ├── MCP / source / tool policy
                              │                                  └── notes / skills / artifacts
                              │
                              └── Outbox ──► OpenViking client boundary
```

Source code is authoritative. The graph is navigation evidence, not behavioral proof. External host tools are optional integrations and are never silently turned into project dependencies.

## Install

### From source

```bash
git clone https://github.com/ryan-brosas/elixir-learning-agent.git
cd elixir-learning-agent
mix deps.get
```

Configure the database and runtime through environment variables; credentials must stay outside the repository. See [`config/config.exs`](config/config.exs) and [`config/runtime.exs`](config/runtime.exs).

### With Docker Compose

```bash
docker compose up --build -d
```

Compose provides PostgreSQL 16, the all-in-one application service, writable state and skill volumes, and an optional `scale-out` worker profile. Source input is mounted read-only through `SOURCE_VOLUME`.

```bash
SOURCE_VOLUME=/absolute/path/to/sources docker compose up --build -d
WORKER_REPLICAS=2 docker compose --profile scale-out up --build -d worker
```

### IDE and MCP integrations

The repository is configured for JetBrains inspection exports in the local, ignored `inspections/` directory and has an IntelliJ MCP Steroid project registration. When those host tools are available, use them for IDE navigation, inspections, run/debug feedback, and structural review; do not add them to `mix.exs`.

The runtime has explicit seams for Codebase Memory and OpenViking. The optional host-side MCP integrations are useful for graph orientation, source verification, prior-art retrieval, and publication checks, but an unavailable MCP server must be recorded as a degraded capability rather than invented as a passing result.

## Usage

The unauthenticated health endpoints are:

- `GET /health/live` — process liveness.
- `GET /health/ready` — database-aware readiness.

The HTTP/API surface includes:

- `GET /` — browser model playground; connection settings can be saved in browser local storage and are never stored by the server.
- `GET /v1/models` — non-secret configured model status; viewer access, or unauthenticated in local dogfood mode.
- `POST /v1/models/list` — discovers provider models from a browser-supplied URL/key; operator access, or unauthenticated in local dogfood mode.
- `POST /v1/models/test` — one bounded, non-tool completion; operator access, or unauthenticated in local dogfood mode. Accepts optional per-request `base_url`, `api_key`, and `model` overrides.
- `GET /v1/repositories` — viewer access.
- `POST /v1/runs/:id/cancel` — operator access.
- `POST /v1/runs/:id/resolve-blocker` — operator access.
- `POST /v1/outbox/:id/retry` — administrator access.

Bearer-token role configuration is environment-driven through `LA_VIEWER_TOKEN`, `LA_OPERATOR_TOKEN`, and `LA_ADMIN_TOKEN`. Model defaults use `LA_MODEL_BASE_URL`, `LA_MODEL`, `LA_MODEL_API_KEY`, and `LA_MODEL_TIMEOUT_MS`, but the playground also accepts URL/key overrides in memory for one request. Never place tokens in source, fixtures, README files, or Qodana configuration.

## Documentation

- [`DESIGN.md`](DESIGN.md) — complete architecture and invariants.
- [`docs/01-domain-state-and-closure.md`](docs/01-domain-state-and-closure.md) — state and honest closure.
- [`docs/02-agent-loop-and-mcp.md`](docs/02-agent-loop-and-mcp.md) — bounded model/tool behavior.
- [`docs/03-storage-artifacts-and-openviking.md`](docs/03-storage-artifacts-and-openviking.md) — persistence and publication.
- [`docs/04-security-deployment-and-observability.md`](docs/04-security-deployment-and-observability.md) — security and operations.
- [`docs/05-testing-and-verification.md`](docs/05-testing-and-verification.md) — acceptance gates.
- [`docs/06-implementation-roadmap.md`](docs/06-implementation-roadmap.md) — delivery status and next milestones.
- [`docs/07-frontend-control-plane.md`](docs/07-frontend-control-plane.md) — browser dogfood surface and planned LiveView control plane.
- [`docs/08-model-routing-workers-and-scaling.md`](docs/08-model-routing-workers-and-scaling.md) — provider and capacity design.
- [`.pi/project.md`](.pi/project.md) — deep verified project context for agents.
- [`.pi/tech-stack.md`](.pi/tech-stack.md) — commands, versions, integrations, and constraints.
- [`AGENTS.md`](AGENTS.md) — short operating spine and canonical completion command.

> **Current status:** the deterministic runtime foundation is implemented and tested. Do not describe the project as a complete autonomous learning product until the open milestones and deployment gates are actually verified.

## License

No license has been selected for this private repository yet. Until a license is added, all rights are reserved; do not redistribute or reuse the code without permission.

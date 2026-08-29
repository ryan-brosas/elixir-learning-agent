# syntax=docker/dockerfile:1

# Standard multi-stage build: compile + release inside a supported hexpm image, then
# copy the release into a minimal runtime. On a normal CI/host with reachable hex,
# `mix deps.get` fetches deps and the release's erledoc matches the runtime glibc.

FROM hexpm/elixir:1.20.4-erlang-29.0.5-debian-trixie-20260824-slim AS build

ENV MIX_ENV=prod
WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix deps.get --only prod && mix deps.compile

COPY . .
RUN mix release

FROM hexpm/elixir:1.20.4-erlang-29.0.5-debian-trixie-20260824-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/sh appuser && mkdir -p /state /agents/skills /sources && chown -R appuser /state /agents/skills /sources

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
WORKDIR /app
COPY --from=build /app/_build/prod/rel/learning_agent ./rel
COPY bin/server ./bin/server

USER appuser
ENV LA_DB_HOST=postgres LA_DB_PORT=5432 LA_HTTP_PORT=4000 PORT=4000
EXPOSE 4000
ENTRYPOINT ["/app/bin/server"]
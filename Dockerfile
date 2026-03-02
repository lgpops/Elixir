# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.18.4

ARG BUILDER_IMAGE="elixir:${ELIXIR_VERSION}"
ARG RUNNER_IMAGE="${BUILDER_IMAGE}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
  apt-get install -y --no-install-recommends build-essential git && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && \
  apt-get install -y --no-install-recommends ca-certificates openssl && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/log_app ./
USER nobody

CMD ["/app/bin/log_app", "start"]

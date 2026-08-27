# hecate-tube
#
# YouTube over mesh -- a channel/video service exercising every macula primitive pair
#
# NO DATA VOLUME AS GENERATED. The scaffold writes nothing, and a named volume
# for data that does not exist is a promise the image cannot keep. Add one
# together with the code that writes it, and declare it here and in the compose
# file at the same time.

# ⚠ THE RUNTIME IS PINNED IN TWO PLACES AND THEY MUST AGREE: here and `lint.yml'
# beside it. A generated service that builds on one release and tests on another
# only ever proves "the tests pass on the CI release".
#
# This template said 27 from the beginning and nothing revisited it, so every
# service scaffolded from it inherited 27 while development machines moved on.
# In `hecate-biotope' that cost three commits of red CI on a crash that does not
# occur on the development release at all, and because `build-push.yml' is a
# separate workflow the image shipped to the fleet regardless.
FROM docker.io/erlang:28-alpine AS builder
WORKDIR /build

# macula ships a QUIC NIF. MACULA_FORCE_SOURCE_BUILD makes it build here rather
# than fetch a prebuilt binary linked against a different libc, which is the
# recorded glibc trap: the fetched artifact loads on the build host and fails on
# alpine at runtime.
#
# This service has its own reckon-db store (store_id/0 + data_dir/0),
# pulling in khepri/ra/reckon_db's own RocksDB-backed native deps.
# erocksdb's CMake build:
#   - openssl-dev: does find_package(OpenSSL) and fails outright without the
#     dev headers (runtime openssl in stage 2 isn't enough).
#   - zstd-dev: without it, falls back to building zstd from a
#     bundled/vendored copy the hex package doesn't actually ship, failing
#     with "No download info given for 'zstd'".
#   - snappy-dev, lz4-dev: unlike zstd, a missing system snappy/lz4 does NOT
#     fail the CMake configure — it silently disables that compression
#     backend and the build succeeds. The break only shows up at RUNTIME
#     (confirmed live 2026-08-27 in a sibling service: barrel_docdb's
#     db_open failed with "specified blob compression type Snappy is not
#     available" the moment a real database was opened). A clean build is
#     not proof this is fixed — only starting the release and opening a
#     store is.
RUN apk add --no-cache git curl bash build-base cmake perl linux-headers openssl-dev zstd-dev snappy-dev lz4-dev
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
ENV RUSTFLAGS="-C target-feature=-crt-static"
ENV MACULA_FORCE_SOURCE_BUILD=1

RUN curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3

# Dependencies resolve from rebar.config alone, so this layer survives every
# change to config/ and apps/ and the Rust toolchain is not re-run per commit.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY apps ./apps
RUN rebar3 as prod release

FROM docker.io/alpine:3.22
# LINKS THE PACKAGE TO THE REPOSITORY. On registries that read it, ghcr among
# them, a package without this label is an orphan: it does not appear on the
# repository page and does not inherit its visibility. A service that shipped
# private by accident failed its first pull with a bare "unauthorized", which
# names nothing and sends you looking in the wrong place.
LABEL org.opencontainers.image.source="https://github.com/hecate-services/hecate-tube"
RUN apk add --no-cache ncurses-libs libstdc++ libgcc openssl ca-certificates curl ffmpeg
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_tube ./

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true

ENV HECATE_NODE_NAME=hecate_tube
ENV HECATE_NODE_HOST=127.0.0.1
ENV HECATE_COOKIE=hecate_tube
ENV HECATE_HEALTH_PORT=8490

VOLUME ["/etc/hecate/secrets"]

EXPOSE 8490
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${HECATE_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/hecate_tube", "foreground"]

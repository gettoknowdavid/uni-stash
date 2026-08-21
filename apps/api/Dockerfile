# syntax=docker/dockerfile:1

# ---- Builder ----
FROM rust:1.97-slim-bookworm AS builder

WORKDIR /app

# System deps needed to compile sqlx (postgres), reqwest/aws-sdk (TLS), etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Cache dependency compilation separately from source changes: copy only the
# manifest first, build a throwaway main.rs against it, so `cargo build`
# here is cached by Docker as long as Cargo.toml/Cargo.lock don't change.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src \
    && echo "fn main() {}" > src/main.rs \
    && echo "// dummy lib for dependency-only build" > src/lib.rs
ENV SQLX_OFFLINE=true
RUN cargo build --release && rm -rf src

# Now bring in the real source and build for real — only this layer
# re-runs when application code changes.
COPY . .
# Force a rebuild of the actual binary (the dummy one is stale/wrong).
RUN touch src/main.rs src/lib.rs && cargo build --release

# ---- Runtime ----
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/uni-stash-be /app/uni-stash-be
# sqlx::migrate!() embeds migrations at compile time via the migrations/
# directory relative to Cargo.toml — this only matters if you're NOT using
# the embedded-migrations macro path, but copying it over is cheap insurance.
COPY --from=builder /app/migrations /app/migrations

RUN useradd --system --no-create-home appuser
USER appuser

EXPOSE 8080
CMD ["/app/uni-stash-be"]

# syntax=docker/dockerfile:1

FROM rust:1.90-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/swamy_sharanam_api /app/swamy_sharanam_api
COPY migrations ./migrations
ENV BIND_ADDR=0.0.0.0:8080
EXPOSE 8080
CMD ["/app/swamy_sharanam_api"]

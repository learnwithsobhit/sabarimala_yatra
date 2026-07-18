#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/infra"
docker compose up -d
cd "$ROOT"
cp -n .env.example .env || true
export $(grep -v '^#' .env | xargs)
cd "$ROOT/apps/api"
cargo run

#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Start minimal Hadoop cluster via docker-compose (requires Docker)
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install Docker and re-run." >&2
  exit 2
fi

echo "Starting Hadoop containers (docker compose up -d)..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d

echo "Waiting 20s for services to initialize..."
sleep 20

# Run top-level pipeline (this will call start_hadoop.sh which will detect docker-compose)
bash "$ROOT_DIR/run_pipeline.sh"

echo "Dry-run finished. Check $ROOT_DIR/output for results."

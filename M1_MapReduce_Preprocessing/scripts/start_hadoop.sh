#!/usr/bin/env bash
set -euo pipefail

# Start Hadoop via docker-compose if present
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT_DIR/docker-compose.yml" ]; then
  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d
  echo "Started docker-compose Hadoop cluster"
  exit 0
fi

if [ -n "${HADOOP_HOME:-}" ]; then
  $HADOOP_HOME/sbin/start-dfs.sh
  $HADOOP_HOME/sbin/start-yarn.sh
  exit 0
fi

echo "No docker-compose.yml and HADOOP_HOME not set. Start Hadoop manually." >&2
exit 1

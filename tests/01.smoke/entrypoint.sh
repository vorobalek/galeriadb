#!/usr/bin/env bash
# Smoke test: one container, wait for readiness, SELECT 1.
# Usage: ./tests/01.smoke/entrypoint.sh [IMAGE]
# IMAGE defaults to galeriadb/11.8:local (use 'make build' first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE="${1:-galeriadb/11.8:local}"
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  log "Image $IMAGE not found. Run 'make build' first."
  exit 1
}
CONTAINER_NAME="galeriadb-smoke-$$"
GALERIA_ROOT_PASSWORD="${GALERIA_ROOT_PASSWORD:-secret}"

cleanup() {
  log "Cleaning up container $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

log "Smoke test: image=$IMAGE"

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$GALERIA_ROOT_PASSWORD" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

log "Waiting for MySQL readiness (up to 60s) via docker exec..."
elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$CONTAINER_NAME" mariadb -u root -p"$GALERIA_ROOT_PASSWORD" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" mariadb -u root -p"$GALERIA_ROOT_PASSWORD" -e "SELECT 1" &>/dev/null; then
  log "MySQL did not become ready within 60s"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
fi

log "Running SELECT 1 (verified)..."
docker exec "$CONTAINER_NAME" mariadb -u root -p"$GALERIA_ROOT_PASSWORD" -e "SELECT 1" || {
  log "SELECT 1 failed"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
}

log "Smoke test passed."

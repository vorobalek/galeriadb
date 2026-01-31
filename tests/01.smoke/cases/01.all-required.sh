#!/usr/bin/env bash
set -euo pipefail

log "Case 01.all-required: all required params present"

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

log "Waiting for MySQL readiness (up to 60s) via docker exec..."
elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
  log "MySQL did not become ready within 60s"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
fi

log "Running SELECT 1 (verified)..."
docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" || {
  log "SELECT 1 failed"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
}

log "Case 01.all-required passed."

#!/usr/bin/env bash
set -euo pipefail

log "Case 05.healthcheck-user: custom healthcheck user/password"

HC_USER="healthcheck"
HC_PASS="healthcheck-pass"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e GALERIA_HEALTHCHECK_USER="$HC_USER" \
  -e GALERIA_HEALTHCHECK_PASSWORD="$HC_PASS" \
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

elapsed=0
while [ "$elapsed" -lt 30 ]; do
  if docker exec "$CONTAINER_NAME" mariadb -u "$HC_USER" -p"$HC_PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" mariadb -u "$HC_USER" -p"$HC_PASS" -e "SELECT 1" &>/dev/null; then
  log "Healthcheck user could not connect"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
fi

log "Waiting for healthcheck endpoint (up to 30s)..."
elapsed=0
while [ "$elapsed" -lt 30 ]; do
  if docker exec "$CONTAINER_NAME" curl -sf http://127.0.0.1:9200 >/dev/null 2>&1; then
    log "Healthcheck OK"
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" curl -sf http://127.0.0.1:9200 >/dev/null 2>&1; then
  log "Healthcheck did not return 200"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
fi

log "Case 05.healthcheck-user passed."

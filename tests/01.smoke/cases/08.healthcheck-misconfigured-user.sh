#!/usr/bin/env bash
set -euo pipefail

log "Case 08.healthcheck-misconfigured-user: health endpoint must be 503 with invalid HC credentials"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e GALERIA_HEALTHCHECK_USER=healthcheck \
  "$IMAGE"

log "Waiting for MySQL readiness (up to 60s)..."
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

code="$(docker exec "$CONTAINER_NAME" sh -lc "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9200/ || true")"
if [ "$code" != "503" ]; then
  log "Expected HTTP 503 from health endpoint, got: $code"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -80
  exit 1
fi

log "Waiting for Docker health status 'unhealthy' (up to 90s)..."
elapsed=0
while [ "$elapsed" -lt 90 ]; do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
  if [ "$status" = "unhealthy" ]; then
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
if [ "$status" != "unhealthy" ]; then
  log "Expected Docker health status 'unhealthy', got '$status'"
  docker inspect "$CONTAINER_NAME" 2>&1 | tail -120
  docker logs "$CONTAINER_NAME" 2>&1 | tail -80
  exit 1
fi

log "Case 08.healthcheck-misconfigured-user passed."

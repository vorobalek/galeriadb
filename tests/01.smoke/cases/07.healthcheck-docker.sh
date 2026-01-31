#!/usr/bin/env bash
set -euo pipefail

log "Case 07.healthcheck-docker: Docker HEALTHCHECK reports healthy when node is ready"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

log "Waiting for Docker health status 'healthy' (up to 90s, start-period=60s)..."
elapsed=0
while [ "$elapsed" -lt 90 ]; do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
  if [ "$status" = "healthy" ]; then
    log "Health status: $status"
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
if [ "$status" != "healthy" ]; then
  log "FAIL: expected health status 'healthy', got '$status'"
  docker inspect "$CONTAINER_NAME" 2>&1 | tail -80
  docker logs "$CONTAINER_NAME" 2>&1 | tail -50
  exit 1
fi

log "Case 07.healthcheck-docker passed."

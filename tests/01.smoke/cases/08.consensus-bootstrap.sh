#!/usr/bin/env bash
set -euo pipefail

log "Case 08.consensus-bootstrap: single node bootstraps via consensus (no static candidate)"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_CONSENSUS_BOOTSTRAP=true \
  -e GALERIA_CONSENSUS_TIMEOUT=3 \
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

log "Verifying node bootstrapped via consensus..."
state=$(docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
if [ "$state" != "Synced" ]; then
  log "Node not Synced: $state"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -50
  exit 1
fi

# Verify the node bootstrapped (wsrep_cluster_address=gcomm:// means bootstrap)
cluster_addr=$(docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -Nse "SHOW VARIABLES LIKE 'wsrep_cluster_address'" 2>/dev/null | awk '{print $2}' || echo "")
if [ "$cluster_addr" != "gcomm://" ]; then
  log "Node did not bootstrap: wsrep_cluster_address=$cluster_addr (expected gcomm://)"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -50
  exit 1
fi
log "OK: node bootstrapped via consensus (wsrep_cluster_address=gcomm://)"

log "Case 08.consensus-bootstrap passed."

#!/usr/bin/env bash
set -euo pipefail

log "Case 11.mariadb-logs-toggle: MariaDB/Galera logs are off by default and enabled with GALERIA_MARIADB_LOGS=on"

OFF_NAME="${CONTAINER_NAME}-off"
ON_NAME="${CONTAINER_NAME}-on"

docker rm -f "$OFF_NAME" "$ON_NAME" 2>/dev/null || true

log "Starting container with default log mode (expected: no WSREP logs in docker logs)..."
docker run -d \
  --name "$OFF_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE" >/dev/null

elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$OFF_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$OFF_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
  log "MySQL did not become ready in default log mode"
  docker logs "$OFF_NAME" 2>&1 | tail -120
  exit 1
fi

logs_off="$(docker logs "$OFF_NAME" 2>&1 || true)"
if echo "$logs_off" | grep -q "WSREP:"; then
  log "Expected no MariaDB/Galera WSREP logs by default, but WSREP lines were found"
  echo "$logs_off" | tail -120
  exit 1
fi

docker rm -f "$OFF_NAME" >/dev/null 2>&1 || true

log "Starting container with GALERIA_MARIADB_LOGS=on (expected: WSREP logs visible)..."
docker run -d \
  --name "$ON_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e GALERIA_MARIADB_LOGS=on \
  "$IMAGE" >/dev/null

elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$ON_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$ON_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
  log "MySQL did not become ready with GALERIA_MARIADB_LOGS=on"
  docker logs "$ON_NAME" 2>&1 | tail -120
  exit 1
fi

logs_on="$(docker logs "$ON_NAME" 2>&1 || true)"
if ! echo "$logs_on" | grep -q "WSREP:"; then
  log "Expected WSREP lines with GALERIA_MARIADB_LOGS=on, but none were found"
  echo "$logs_on" | tail -120
  exit 1
fi

docker rm -f "$ON_NAME" >/dev/null 2>&1 || true

log "Case 11.mariadb-logs-toggle passed."

#!/usr/bin/env bash
set -euo pipefail

log "Case 06.graceful-shutdown: SIGTERM leads to clean shutdown, data persists"

VOL_NAME="galeriadb-smoke-graceful-$$"
docker volume create "$VOL_NAME" >/dev/null

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -v "$VOL_NAME:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
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
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker volume rm "$VOL_NAME" 2>/dev/null || true
  exit 1
fi

docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "
  CREATE DATABASE IF NOT EXISTS testdb;
  USE testdb;
  DROP TABLE IF EXISTS graceful_test;
  CREATE TABLE graceful_test (id INT PRIMARY KEY, v VARCHAR(32));
  INSERT INTO graceful_test VALUES (1, 'before-stop');
"

log "Stopping container (SIGTERM)..."
docker stop -t 30 "$CONTAINER_NAME"
docker rm "$CONTAINER_NAME"

log "Starting new container with same volume..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -v "$VOL_NAME:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

log "Waiting for MySQL readiness after restart (up to 60s)..."
elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
  log "MySQL did not become ready after restart"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker volume rm "$VOL_NAME" 2>/dev/null || true
  exit 1
fi

val="$(docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM graceful_test WHERE id=1" 2>/dev/null || echo "")"
if [ "$val" != "before-stop" ]; then
  log "Data mismatch after restart: expected 'before-stop', got '$val'"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -50
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker volume rm "$VOL_NAME" 2>/dev/null || true
  exit 1
fi

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker volume rm "$VOL_NAME" 2>/dev/null || true

log "Case 06.graceful-shutdown passed."

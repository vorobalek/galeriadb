#!/usr/bin/env bash
log "Case 07.auto-migrate-with-backup: 11.8 -> 12.1 with pre-upgrade S3 backup"

start_minio

OLD_IMAGE="galeriadb/11.8:latest"
NEW_IMAGE="$IMAGE"

log "Pulling old image: $OLD_IMAGE"
docker pull "$OLD_IMAGE" >/dev/null

UPGRADE_VOL="galera-upgrade-$$"
register_volume "$UPGRADE_VOL"
docker volume create "$UPGRADE_VOL" >/dev/null

start_old_node() {
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -v "$UPGRADE_VOL:/var/lib/mysql" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    -e GALERIA_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
    -e AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
    -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
    -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "$OLD_IMAGE"
}

start_new_node() {
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -v "$UPGRADE_VOL:/var/lib/mysql" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    -e GALERIA_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
    -e AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
    -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
    -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "$NEW_IMAGE"
}

wait_upgrade_done() {
  local timeout="${1:-180}"
  local elapsed=0 info
  log "Waiting for auto-migrate completion (up to ${timeout}s)..."
  while [ "$elapsed" -lt "$timeout" ]; do
    info=$(docker exec "$GALERA_NAME" sh -c "cat /var/lib/mysql/mysql_upgrade_info 2>/dev/null || cat /var/lib/mysql/mariadb_upgrade_info 2>/dev/null || true")
    if echo "$info" | grep -q "12.1"; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  log "Auto-migrate did not complete in time"
  return 1
}

log "Starting 11.8 node..."
start_old_node
wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}
wait_synced || {
  docker logs "$GALERA_NAME" 2>&1 | tail -50
  exit 1
}

log "Creating S3 bucket..."
docker exec "$GALERA_NAME" aws s3 mb "s3://${S3_BUCKET}" 2>/dev/null || true

log "Creating test data..."
docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_upgrade; CREATE TABLE ci_upgrade (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_upgrade VALUES (1, 'before-upgrade');"

log "Stopping 11.8 node..."
docker rm -f "$GALERA_NAME" >/dev/null 2>&1 || true

log "Starting 12.1 node..."
start_new_node
wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}
wait_synced || {
  docker logs "$GALERA_NAME" 2>&1 | tail -50
  exit 1
}
wait_upgrade_done 240 || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}

val=$(docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_upgrade WHERE id=1" 2>/dev/null || echo "")
if [ "$val" != "before-upgrade" ]; then
  log "Auto-migrate failed: expected 'before-upgrade', got '$val'"
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
fi

list=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/galera1/" 2>/dev/null || echo "")
if ! echo "$list" | grep -q '\.tar\.gz'; then
  log "No backup found after auto-migrate. Listing: $list"
  exit 1
fi

log "Case 07.auto-migrate-with-backup passed."

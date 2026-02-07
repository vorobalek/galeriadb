#!/usr/bin/env bash
log "Case 09.auto-migrate-fails-when-backup-fails: backup failure must block upgrade"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio

OLD_IMAGE="galeriadb/11.8:latest"
NEW_IMAGE="$IMAGE"

log "Pulling old image: $OLD_IMAGE"
docker pull "$OLD_IMAGE" >/dev/null

UPGRADE_FAIL_VOL="galera-upgrade-fail-$$"
register_volume "$UPGRADE_FAIL_VOL"
docker volume create "$UPGRADE_FAIL_VOL" >/dev/null

start_old_node() {
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -v "$UPGRADE_FAIL_VOL:/var/lib/mysql" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    "$OLD_IMAGE"
}

start_new_node_with_broken_backup() {
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -v "$UPGRADE_FAIL_VOL:/var/lib/mysql" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    -e GALERIA_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
    -e AWS_ENDPOINT_URL="http://missing-minio:9000" \
    -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
    -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "$NEW_IMAGE"
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

log "Creating test data in 11.8 datadir..."
docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_upgrade_fail; CREATE TABLE ci_upgrade_fail (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_upgrade_fail VALUES (1, 'before-failed-upgrade');"

log "Stopping 11.8 node..."
docker rm -f "$GALERA_NAME" >/dev/null 2>&1 || true

log "Starting 12.1 node with intentionally broken S3 endpoint..."
start_new_node_with_broken_backup

log "Waiting for container to exit with failure (up to 240s)..."
elapsed=0
running="true"
while [ "$elapsed" -lt 240 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$GALERA_NAME" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

if [ "$running" = "true" ]; then
  log "Expected startup failure, but container is still running"
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
fi

exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$GALERA_NAME" 2>/dev/null || echo "0")"
if [ "$exit_code" = "0" ]; then
  log "Expected non-zero exit code when pre-upgrade backup fails, got: $exit_code"
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
fi

logs="$(docker logs "$GALERA_NAME" 2>&1 || true)"
if ! echo "$logs" | grep -q "Auto-migrate: running pre-upgrade backup"; then
  log "Expected auto-migrate backup attempt in logs"
  echo "$logs" | tail -120
  exit 1
fi
if echo "$logs" | grep -q "Auto-migrate: upgrade complete"; then
  log "Upgrade unexpectedly completed despite failed backup"
  echo "$logs" | tail -120
  exit 1
fi

upgrade_info="$(
  docker run --rm \
    -v "$UPGRADE_FAIL_VOL:/var/lib/mysql" \
    --entrypoint sh \
    "$NEW_IMAGE" \
    -c "cat /var/lib/mysql/mysql_upgrade_info 2>/dev/null || cat /var/lib/mysql/mariadb_upgrade_info 2>/dev/null || true"
)"
if echo "$upgrade_info" | grep -q "12.1"; then
  log "Expected upgrade info to remain pre-12.1 after failed backup, got: ${upgrade_info:-<empty>}"
  exit 1
fi

log "Case 09.auto-migrate-fails-when-backup-fails passed."

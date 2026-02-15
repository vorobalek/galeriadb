#!/usr/bin/env bash
log "Case 10.bucket-path-backup-clone: backup+clone scripts with bucket/path variables"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio

S3_PATH_MODE="mariadb-path-mode"
BACKUP_VOL="galera-path-backup-$$"
RESTORE_VOL="galera-path-restore-$$"
register_volume "$BACKUP_VOL"
register_volume "$RESTORE_VOL"
docker volume create "$BACKUP_VOL" >/dev/null
docker volume create "$RESTORE_VOL" >/dev/null

log "Starting node in backup mode (bucket+path)..."
docker run -d \
  --name "$GALERA_NAME" \
  --hostname galera1 \
  --network "$NET_NAME" \
  -v "$BACKUP_VOL:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e GALERIA_BACKUP_S3_BUCKET="$S3_BUCKET" \
  -e GALERIA_BACKUP_S3_PATH="$S3_PATH_MODE" \
  -e AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
  -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
  -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
  -e AWS_DEFAULT_REGION=us-east-1 \
  "$IMAGE"

wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
}
wait_synced || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}

log "Creating S3 bucket..."
docker exec "$GALERA_NAME" aws s3 mb "s3://${S3_BUCKET}" 2>/dev/null || true

log "Creating test data..."
docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_path_mode; CREATE TABLE ci_path_mode (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_path_mode VALUES (1, 'path-mode-ok');"

log "Running backup script (bucket+path)..."
docker exec -e MYSQL_PWD="$PASS" "$GALERA_NAME" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh failed in bucket+path mode"
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
}

list=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PATH_MODE}/galera1/" 2>/dev/null || echo "")
if ! echo "$list" | grep -q '\.tar\.gz'; then
  log "No backup object found under bucket+path mode. Listing: $list"
  exit 1
fi
latest="$(echo "$list" | awk '{print $4}' | sort | tail -1)"
if [ -z "${latest:-}" ]; then
  log "Failed to determine latest backup object in bucket+path mode"
  exit 1
fi

log "Restoring backup into a clean volume with galera-clone.sh (bucket+path)..."
docker run --rm \
  --network "$NET_NAME" \
  -v "$RESTORE_VOL:/var/lib/mysql" \
  -e GALERIA_CLONE_BACKUP_S3_BUCKET="$S3_BUCKET" \
  -e GALERIA_CLONE_BACKUP_S3_PATH="$S3_PATH_MODE" \
  -e GALERIA_CLONE_FROM="galera1/${latest}" \
  -e CLONE_AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
  -e CLONE_AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
  -e CLONE_AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
  -e CLONE_AWS_DEFAULT_REGION=us-east-1 \
  --entrypoint sh \
  "$IMAGE" \
  -c "rm -rf /var/lib/mysql/* && /usr/local/bin/galera-clone.sh"

log "Starting node from restored volume..."
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker run -d \
  --name "$GALERA_NAME" \
  --hostname galera1 \
  --network "$NET_NAME" \
  -v "$RESTORE_VOL:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
}

val=""
for attempt in {1..30}; do
  val="$(docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_path_mode WHERE id=1" 2>/dev/null || echo "")"
  if [ "$val" = "path-mode-ok" ]; then
    break
  fi
  [ "$attempt" -lt 30 ] && sleep 1
done
if [ "$val" != "path-mode-ok" ]; then
  log "Restored data mismatch in bucket+path mode: expected 'path-mode-ok', got '$val'"
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
fi

log "Case 10.bucket-path-backup-clone passed."

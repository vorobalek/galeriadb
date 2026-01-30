#!/usr/bin/env bash
# Case: run galera-backup.sh and verify .tar.gz object in S3.
# Sourced from entrypoint. Uses 00.common.sh (start_minio, start_galera, wait_mysql_ready, wait_synced, GALERA_NAME, PASS, S3_BUCKET, S3_PREFIX).

log "Case 01.backup-to-s3: backup and verify in S3"
start_minio
start_galera
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

log "Running galera-backup.sh..."
docker exec -e MYSQL_PWD="$PASS" "$GALERA_NAME" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh failed"
  docker logs "$GALERA_NAME" 2>&1 | tail -30
  exit 1
}

log "Verifying backup object in S3..."
list=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null || echo "")
if ! echo "$list" | grep -q '\.tar\.gz'; then
  log "No .tar.gz backup found in S3. Listing: $list"
  exit 1
fi
log "Case 01.backup-to-s3 passed."

#!/usr/bin/env bash
log "Case 03.retention-deletes-old: retention deletes by S3 LastModified"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true
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

log "Running first backup (creates one object with LastModified = now)..."
docker exec -e MYSQL_PWD="$PASS" "$GALERA_NAME" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh failed"
  docker logs "$GALERA_NAME" 2>&1 | tail -30
  exit 1
}

count_before=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null | grep -c '\.tar\.gz' || true)
if [ "${count_before:-0}" -lt 1 ]; then
  log "Expected at least one .tar.gz after first backup, got: $count_before"
  exit 1
fi
log "Backups before retention run: $count_before"

# Use a future cutoff so all current objects are treated as old (portable across GNU/BSD date).
FUTURE_CUTOFF="2030-01-01"
log "Running backup again with RETENTION_DAYS=1 and CUTOFF_OVERRIDE=$FUTURE_CUTOFF (simulate retention)..."
docker exec \
  -e MYSQL_PWD="$PASS" \
  -e GALERIA_BACKUP_RETENTION_DAYS=1 \
  -e GALERIA_BACKUP_RETENTION_CUTOFF_OVERRIDE="$FUTURE_CUTOFF" \
  "$GALERA_NAME" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh (with retention) failed"
  docker logs "$GALERA_NAME" 2>&1 | tail -30
  exit 1
}

count_after=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null | grep -c '\.tar\.gz' || true)
if [ "${count_after:-0}" -ne 1 ]; then
  log "Expected exactly 1 backup after retention (old ones deleted), got: $count_after"
  docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null || true
  exit 1
fi
log "Case 03.retention-deletes-old passed (old backups deleted by S3 LastModified, one new backup kept)."

#!/usr/bin/env bash
log "Case 04.cron-backup: wait for cron (* * * * *) to run backup and verify S3"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true
start_minio
GALERIA_BACKUP_SCHEDULE='* * * * *' start_galera
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

log "Waiting for cron to run backup (up to 150s)..."
elapsed=0
while [ "$elapsed" -lt 150 ]; do
  list=$(docker exec "$GALERA_NAME" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null || echo "")
  if echo "$list" | grep -q '\.tar\.gz'; then
    log "Backup found in S3 after ${elapsed}s (cron ran successfully)"
    log "Case 04.cron-backup passed."
    exit 0
  fi
  sleep 10
  elapsed=$((elapsed + 10))
done

log "No backup in S3 after ${elapsed}s; cron may not have run or backup failed"
docker exec "$GALERA_NAME" tail -80 /var/log/galera-backup.log 2>/dev/null || true
exit 1

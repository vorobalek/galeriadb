#!/usr/bin/env bash
log "Case 02.fail-without-s3-config: expect error when S3 not configured"
# Ensure stack is running (may already be started by case 01 in sequential run)
if ! docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
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
fi
out=$(docker exec -e MYSQL_PWD="$PASS" -e GALERIA_BACKUP_S3_URI= -e GALERIA_BACKUP_S3_BUCKET= \
  "$GALERA_NAME" /usr/local/bin/galera-backup.sh 2>&1) || true
if ! echo "$out" | grep -q "GALERIA_BACKUP_S3_URI\|GALERIA_BACKUP_S3_BUCKET"; then
  log "Expected error message when S3 not configured; got: $out"
  exit 1
fi
log "Case 02.fail-without-s3-config passed."

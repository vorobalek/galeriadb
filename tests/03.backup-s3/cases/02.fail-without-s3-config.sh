#!/usr/bin/env bash
# Case: run galera-backup.sh without S3 config; expect error message.
# Sourced from entrypoint after 01.backup-to-s3 (same GALERA_NAME container). Uses GALERA_NAME, PASS from 00.common.

log "Case 02.fail-without-s3-config: expect error when S3 not configured"
out=$(docker exec -e MYSQL_PWD="$PASS" -e GALERIA_BACKUP_S3_URI= -e GALERIA_BACKUP_S3_BUCKET= \
  "$GALERA_NAME" /usr/local/bin/galera-backup.sh 2>&1) || true
if ! echo "$out" | grep -q "GALERIA_BACKUP_S3_URI\|GALERIA_BACKUP_S3_BUCKET"; then
  log "Expected error message when S3 not configured; got: $out"
  exit 1
fi
log "Case 02.fail-without-s3-config passed."

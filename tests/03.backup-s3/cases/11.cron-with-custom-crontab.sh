#!/usr/bin/env bash
log "Case 11.cron-with-custom-crontab: install backup cron together with GALERIA_CRONTAB"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio
GALERIA_BACKUP_SCHEDULE='* * * * *' GALERIA_CRONTAB='*/5 * * * * echo custom-task >> /tmp/custom-cron.log' start_galera
wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -120
  exit 1
}

crontab_body="$(docker exec "$GALERA_NAME" crontab -l 2>/dev/null || true)"
if ! echo "$crontab_body" | grep -q '/usr/local/bin/galera-backup.sh'; then
  log "Backup cron line not found in crontab: $crontab_body"
  exit 1
fi
if ! echo "$crontab_body" | grep -q 'custom-task'; then
  log "Custom GALERIA_CRONTAB line not found in crontab: $crontab_body"
  exit 1
fi

log "Case 11.cron-with-custom-crontab passed."

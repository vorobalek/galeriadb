#!/usr/bin/env bash
# Setup cron for hot backups to S3. Writes env file and installs crontab.
# Called by entrypoint.sh when GALERIA_BACKUP_SCHEDULE and S3 destination are set.
# Expects GALERIA_BACKUP_* and AWS_* (and MYSQL_PWD) in environment.

set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

ENV_FILE="/run/galera-backup.env"
{
  echo "export MYSQL_PWD=\"${MYSQL_PWD}\""
  [ -n "${GALERIA_BACKUP_S3_URI:-}" ] && echo "export GALERIA_BACKUP_S3_URI=\"${GALERIA_BACKUP_S3_URI}\""
  [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ] && echo "export GALERIA_BACKUP_S3_BUCKET=\"${GALERIA_BACKUP_S3_BUCKET}\""
  [ -n "${GALERIA_BACKUP_S3_PATH:-}" ] && echo "export GALERIA_BACKUP_S3_PATH=\"${GALERIA_BACKUP_S3_PATH}\""
  [ -n "${GALERIA_BACKUP_TMPDIR:-}" ] && echo "export GALERIA_BACKUP_TMPDIR=\"${GALERIA_BACKUP_TMPDIR}\""
  [ -n "${GALERIA_BACKUP_RETENTION_DAYS:-}" ] && echo "export GALERIA_BACKUP_RETENTION_DAYS=\"${GALERIA_BACKUP_RETENTION_DAYS}\""
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && echo "export AWS_ACCESS_KEY_ID=\"${AWS_ACCESS_KEY_ID}\""
  [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && echo "export AWS_SECRET_ACCESS_KEY=\"${AWS_SECRET_ACCESS_KEY}\""
  [ -n "${AWS_DEFAULT_REGION:-}" ] && echo "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\""
  [ -n "${AWS_REGION:-}" ] && echo "export AWS_REGION=\"${AWS_REGION}\""
  [ -n "${AWS_ENDPOINT_URL:-}" ] && echo "export AWS_ENDPOINT_URL=\"${AWS_ENDPOINT_URL}\""
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

CRON_LINE="${GALERIA_BACKUP_SCHEDULE} . ${ENV_FILE} && /usr/local/bin/galera-backup.sh >> /var/log/galera-backup.log 2>&1"
if [ -n "${GALERIA_CRONTAB:-}" ]; then
  ( echo "$CRON_LINE"; echo "$GALERIA_CRONTAB" ) | crontab -
else
  echo "$CRON_LINE" | crontab -
fi
cron &
log "Backup cron enabled: $GALERIA_BACKUP_SCHEDULE"

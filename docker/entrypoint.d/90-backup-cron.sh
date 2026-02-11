#!/usr/bin/env bash

if [ -n "${GALERIA_BACKUP_SCHEDULE:-}" ] && backup_configured; then
  log "Enabling backup cron: $GALERIA_BACKUP_SCHEDULE"

  BACKUP_ENV_VARS=(
    GALERIA_ROOT_PASSWORD
    GALERIA_BACKUP_S3_URI
    GALERIA_BACKUP_S3_BUCKET
    GALERIA_BACKUP_S3_PATH
    GALERIA_BACKUP_TMPDIR
    GALERIA_BACKUP_RETENTION_DAYS
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_DEFAULT_REGION
    AWS_REGION
    AWS_ENDPOINT_URL
  )

  ENV_FILE="/run/galera-backup.env"
  {
    echo "export PATH=\"/usr/local/bin:/usr/bin:/bin:\$PATH\""
    for var in "${BACKUP_ENV_VARS[@]}"; do
      [ -n "${!var:-}" ] && echo "export ${var}=\"${!var}\""
    done
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"

  CRON_LINE="${GALERIA_BACKUP_SCHEDULE} . ${ENV_FILE} && /usr/local/bin/galera-backup.sh >> /var/log/galera-backup.log 2>&1"
  if [ -n "${GALERIA_CRONTAB:-}" ]; then
    (
      echo "$CRON_LINE"
      echo "$GALERIA_CRONTAB"
    ) | crontab -
  else
    echo "$CRON_LINE" | crontab -
  fi
  cron &
  log "Backup cron enabled: $GALERIA_BACKUP_SCHEDULE"
fi

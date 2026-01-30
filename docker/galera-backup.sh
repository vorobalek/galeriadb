#!/usr/bin/env bash
# Hot backup of MariaDB Galera to S3. Run manually or via cron.
# Requires: node in Synced state, GALERIA_BACKUP_S3_URI or GALERIA_BACKUP_S3_BUCKET, AWS credentials (or IAM role).
# See README for all GALERIA_BACKUP_* env vars.

set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

: "${MYSQL_PWD:?MYSQL_PWD is required for backup}"

# Backup destination: full URI or bucket + path
if [ -n "${GALERIA_BACKUP_S3_URI:-}" ]; then
  S3_BASE="${GALERIA_BACKUP_S3_URI}"
elif [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ]; then
  S3_BASE="s3://${GALERIA_BACKUP_S3_BUCKET}/${GALERIA_BACKUP_S3_PATH:-mariadb}"
else
  log "ERROR: Set GALERIA_BACKUP_S3_URI or GALERIA_BACKUP_S3_BUCKET to enable S3 backup"
  exit 1
fi

HOST="${HOSTNAME:-unknown}"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
TMP="${GALERIA_BACKUP_TMPDIR:-/tmp}/backup-${TS}"
OUT="${GALERIA_BACKUP_TMPDIR:-/tmp}/mariadb-${HOST}-${TS}.tar.gz"

# 1) Only backup from a Synced node
STATE=$(mariadb -uroot -Nse "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || true)
if [ "$STATE" != "Synced" ]; then
  log "SKIP: node not Synced (wsrep_local_state_comment=$STATE)"
  exit 0
fi

# 2) Hot backup
mkdir -p "$TMP"
mariabackup --backup \
  --target-dir="$TMP" \
  --user=root --password="$MYSQL_PWD" \
  --galera-info

# 3) Compress
tar -C "$TMP" -czf "$OUT" .

# 4) Upload to S3
S3_PATH="${S3_BASE}/${HOST}/${TS}.tar.gz"
AWS_OPTS=()
[ -n "${AWS_ENDPOINT_URL:-}" ] && AWS_OPTS+=(--endpoint-url "$AWS_ENDPOINT_URL")
aws s3 cp "$OUT" "$S3_PATH" "${AWS_OPTS[@]}"

# 5) Optional: delete backups older than GALERIA_BACKUP_RETENTION_DAYS
if [ -n "${GALERIA_BACKUP_RETENTION_DAYS:-}" ] && [ "$GALERIA_BACKUP_RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
  CUTOFF=$(date -u -d "now - ${GALERIA_BACKUP_RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null || true)
  if [ -n "$CUTOFF" ]; then
    aws s3 ls "${S3_BASE}/${HOST}/" "${AWS_OPTS[@]}" 2>/dev/null | while read -r _ _ _ key; do
      [ -z "$key" ] && continue
      key_date="${key:0:10}"
      if [[ "$key_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$key_date" < "$CUTOFF" ]]; then
        if aws s3 rm "${S3_BASE}/${HOST}/${key}" "${AWS_OPTS[@]}" 2>/dev/null; then
          log "Deleted old backup: ${key}"
        fi
      fi
    done
  fi
fi

# 6) Cleanup
rm -rf "$TMP" "$OUT"
log "OK: uploaded $S3_PATH"

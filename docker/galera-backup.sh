#!/usr/bin/env bash
# Hot backup to S3.

set -euo pipefail

# shellcheck source=galera-lib.sh
source "$(dirname "$0")/galera-lib.sh"

: "${GALERIA_ROOT_PASSWORD:?GALERIA_ROOT_PASSWORD is required for backup}"
MYSQL_PWD="${GALERIA_ROOT_PASSWORD}"

resolve_s3_base \
  GALERIA_BACKUP_S3_URI GALERIA_BACKUP_S3_BUCKET GALERIA_BACKUP_S3_PATH mariadb \
  "Set GALERIA_BACKUP_S3_URI or GALERIA_BACKUP_S3_BUCKET to enable S3 backup"

HOST="${HOSTNAME:-unknown}"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
TMP="${GALERIA_BACKUP_TMPDIR:-/tmp}/backup-${TS}"
OUT="${GALERIA_BACKUP_TMPDIR:-/tmp}/mariadb-${HOST}-${TS}.tar.gz"

STATE=$(mariadb -uroot -Nse "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || true)
if [ "$STATE" != "Synced" ]; then
  log "SKIP: node not Synced (wsrep_local_state_comment=$STATE)"
  exit 0
fi

mkdir -p "$TMP"
mariadb-backup --backup \
  --target-dir="$TMP" \
  --user=root --password="$MYSQL_PWD" \
  --galera-info

tar -C "$TMP" -czf "$OUT" .

# Retention uses S3 LastModified (from aws s3 ls), not filenames.
build_aws_opts AWS_ENDPOINT_URL
# Do not abort if ls/rm fails (e.g. first run, no prefix yet).
if [ -n "${GALERIA_BACKUP_RETENTION_DAYS:-}" ] && [ "$GALERIA_BACKUP_RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
  CUTOFF="${GALERIA_BACKUP_RETENTION_CUTOFF_OVERRIDE:-$(date -u -d "now - ${GALERIA_BACKUP_RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null)}"
  if [ -n "$CUTOFF" ]; then
    aws s3 ls "${S3_BASE}/${HOST}/" "${AWS_OPTS[@]}" 2>/dev/null | while read -r obj_date _ _ key; do
      [ -z "$key" ] && continue
      if [[ "$obj_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$obj_date" < "$CUTOFF" ]]; then
        if aws s3 rm "${S3_BASE}/${HOST}/${key}" "${AWS_OPTS[@]}" 2>/dev/null; then
          log "Deleted old backup: ${key}"
        fi
      fi
    done || true
  fi
fi

S3_PATH="${S3_BASE}/${HOST}/${TS}.tar.gz"
aws s3 cp "$OUT" "$S3_PATH" "${AWS_OPTS[@]}"

rm -rf "$TMP" "$OUT"
log "OK: uploaded $S3_PATH"

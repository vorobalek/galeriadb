#!/usr/bin/env bash
# Restore MariaDB data directory from an S3 backup.

set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

if [ -n "${GALERIA_CLONE_BACKUP_S3_URI:-}" ]; then
  S3_BASE="${GALERIA_CLONE_BACKUP_S3_URI}"
elif [ -n "${GALERIA_CLONE_BACKUP_S3_BUCKET:-}" ]; then
  S3_BASE="s3://${GALERIA_CLONE_BACKUP_S3_BUCKET}/${GALERIA_CLONE_BACKUP_S3_PATH:-mariadb}"
else
  log "ERROR: Set GALERIA_CLONE_BACKUP_S3_URI or GALERIA_CLONE_BACKUP_S3_BUCKET to enable restore"
  exit 1
fi

AWS_OPTS=()
[ -n "${CLONE_AWS_ENDPOINT_URL:-}" ] && AWS_OPTS+=(--endpoint-url "$CLONE_AWS_ENDPOINT_URL")

aws_env=()
[ -n "${CLONE_AWS_ACCESS_KEY_ID:-}" ] && aws_env+=(AWS_ACCESS_KEY_ID="$CLONE_AWS_ACCESS_KEY_ID")
[ -n "${CLONE_AWS_SECRET_ACCESS_KEY:-}" ] && aws_env+=(AWS_SECRET_ACCESS_KEY="$CLONE_AWS_SECRET_ACCESS_KEY")
[ -n "${CLONE_AWS_DEFAULT_REGION:-}" ] && aws_env+=(AWS_DEFAULT_REGION="$CLONE_AWS_DEFAULT_REGION")
[ -n "${CLONE_AWS_REGION:-}" ] && aws_env+=(AWS_REGION="$CLONE_AWS_REGION")

aws_cmd() {
  "${aws_env[@]}" aws "$@"
}

if [ -n "${GALERIA_CLONE_FROM:-}" ]; then
  if [[ "${GALERIA_CLONE_FROM}" == s3://* ]]; then
    S3_OBJ="${GALERIA_CLONE_FROM}"
  else
    S3_OBJ="${S3_BASE}/${GALERIA_CLONE_FROM}"
  fi
else
  HOST="${HOSTNAME:-unknown}"
  PREFIX="${S3_BASE}/${HOST}/"
  log "Selecting latest backup under ${PREFIX}"
  latest=$(
    aws_cmd s3 ls "${PREFIX}" "${AWS_OPTS[@]}" 2>/dev/null | awk '$4 ~ /\.tar\.gz$/ {print $4}' | sort | tail -1
  )
  if [ -z "${latest:-}" ]; then
    log "ERROR: No backups found under ${PREFIX}"
    exit 1
  fi
  S3_OBJ="${PREFIX}${latest}"
fi

TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
TMP_BASE="${GALERIA_CLONE_TMPDIR:-/tmp}"
WORKDIR="${TMP_BASE}/clone-${TS}"
TAR_PATH="${TMP_BASE}/clone-${TS}.tar.gz"

mkdir -p "$WORKDIR"
log "Downloading backup: ${S3_OBJ}"
aws_cmd s3 cp "${S3_OBJ}" "${TAR_PATH}" "${AWS_OPTS[@]}"

tar -C "$WORKDIR" -xzf "$TAR_PATH"
rm -f "$TAR_PATH"

log "Preparing backup..."
mariadb-backup --prepare --target-dir="$WORKDIR"

log "Copying back to /var/lib/mysql..."
mariadb-backup --copy-back --target-dir="$WORKDIR" --datadir=/var/lib/mysql
chown -R mysql:mysql /var/lib/mysql

rm -rf "$WORKDIR"
log "OK: restored from ${S3_OBJ}"

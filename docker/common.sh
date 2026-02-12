#!/usr/bin/env bash

DATA_DIR="/var/lib/mysql"
export DATA_DIR

log() { echo "[$(date -Is)] $*"; }

read_local_seqno() {
  local grastate="${DATA_DIR}/grastate.dat"
  if [ -f "$grastate" ]; then
    awk -F: '/^seqno:/{gsub(/[[:space:]]/, "", $2); print $2}' "$grastate" 2>/dev/null || echo "-1"
  else
    echo "-1"
  fi
}

backup_configured() {
  [ -n "${GALERIA_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ]
}

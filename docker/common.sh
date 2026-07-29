#!/usr/bin/env bash

DATA_DIR="/var/lib/mysql"
export DATA_DIR

log() { echo "[$(date -Is)] $*"; }

backup_configured() {
  [ -n "${GALERIA_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ]
}

# True while a state snapshot transfer runs on this node. MariaDB keeps the
# wsrep_sst_<method> helper alive for the whole transfer, so a matching process
# means the server is busy receiving data, not stuck.
sst_in_progress() {
  local proc cmdline
  for proc in /proc/[0-9]*/cmdline; do
    cmdline="$(tr '\0' ' ' 2>/dev/null <"$proc")" || continue
    case "$cmdline" in
      *wsrep_sst_*) return 0 ;;
    esac
  done
  return 1
}

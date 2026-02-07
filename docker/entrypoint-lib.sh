#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
export DATA_DIR

log() { echo "[$(date -Is)] $*"; }

require_env() {
  local var
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: Required environment variable $var is not set. Set it to start the container (e.g. GALERIA_PEERS=tasks.galera, GALERIA_ROOT_PASSWORD=your-secret, GALERIA_BOOTSTRAP_CANDIDATE=galera-node-a)." >&2
      exit 1
    fi
  done
}

is_datadir_empty() {
  shopt -s nullglob dotglob
  local entries=("$DATA_DIR"/*)
  shopt -u nullglob dotglob
  if [ "${#entries[@]}" -eq 0 ]; then
    return 0
  fi
  if [ "${#entries[@]}" -eq 1 ] && [ "$(basename "${entries[0]}")" = "lost+found" ]; then
    return 0
  fi
  return 1
}

clone_enabled() {
  [ -n "${GALERIA_CLONE_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_CLONE_BACKUP_S3_BUCKET:-}" ]
}

wait_for_mysql() {
  for _ in $(seq 1 60); do
    if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_stage() {
  local stage="$1"
  shift
  set -- "$@"
  # shellcheck source=/dev/null
  source "${ENTRYPOINT_DIR}/${stage}"
}

shutdown() {
  log "Received signal, shutting down MariaDB..."
  kill -TERM "$MYSQLD_PID" 2>/dev/null || true
  wait "$MYSQLD_PID" 2>/dev/null || true
  exit 0
}

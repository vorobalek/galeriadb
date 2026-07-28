#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

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

# wait_for_mysql [TIMEOUT] [MYSQLD_PID]
# A joiner refuses connections for as long as SST takes, so time spent in a
# state transfer does not count against TIMEOUT (and the countdown restarts
# once the transfer ends). The transfer itself is bounded by
# GALERIA_SST_TIMEOUT (0 = no bound).
wait_for_mysql() {
  local timeout="${1:-60}"
  local pid="${2:-}"
  local sst_timeout="${GALERIA_SST_TIMEOUT:-3600}"
  local elapsed=0 sst_elapsed=0 in_sst=0
  while true; do
    if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
      return 0
    fi
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    if sst_in_progress; then
      if [ "$in_sst" -eq 0 ]; then
        in_sst=1
        if [ "$sst_timeout" -gt 0 ]; then
          log "State transfer (SST) in progress; readiness timeout paused (SST limit ${sst_timeout}s)"
        else
          log "State transfer (SST) in progress; readiness timeout paused (no SST limit)"
        fi
      fi
      sst_elapsed=$((sst_elapsed + 1))
      if [ "$sst_timeout" -gt 0 ] && [ "$sst_elapsed" -ge "$sst_timeout" ]; then
        log "State transfer did not finish within ${sst_timeout}s (GALERIA_SST_TIMEOUT)"
        return 1
      fi
    else
      if [ "$in_sst" -eq 1 ]; then
        in_sst=0
        elapsed=0
        log "State transfer finished after ${sst_elapsed}s; waiting up to ${timeout}s for MariaDB to accept connections"
      fi
      if [ "$elapsed" -ge "$timeout" ]; then
        return 1
      fi
      elapsed=$((elapsed + 1))
    fi
    # Poll for a starting transfer in slices: a small dataset transfers in a
    # couple of seconds, and a once-per-second check can miss that window.
    for _ in 1 2 3 4 5; do
      sleep 0.2
      if [ "$in_sst" -eq 0 ] && sst_in_progress; then
        break
      fi
    done
  done
}

wait_for_synced() {
  local timeout="${1:-120}"
  local elapsed=0 state ready
  while [ "$elapsed" -lt "$timeout" ]; do
    state=$(mariadb -u root -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
    ready=$(mariadb -u root -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_ready'" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$state" = "Synced" ] && [ "$ready" = "ON" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
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

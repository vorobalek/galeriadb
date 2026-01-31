#!/bin/bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }
DATA_DIR="/var/lib/mysql"

# Required environment variables (no defaults; container will not start without them)
for req in GALERIA_PEERS GALERIA_ROOT_PASSWORD GALERIA_BOOTSTRAP_CANDIDATE; do
  if [ -z "${!req:-}" ]; then
    echo "ERROR: Required environment variable $req is not set. Set it to start the container (e.g. GALERIA_PEERS=tasks.galera, GALERIA_ROOT_PASSWORD=your-secret, GALERIA_BOOTSTRAP_CANDIDATE=galera-node-a)." >&2
    exit 1
  fi
done

: "${GALERIA_CLUSTER_NAME:=galera_cluster}"
: "${GALERIA_DISCOVERY_TIMEOUT:=5}"
: "${GALERIA_DISCOVERY_INTERVAL:=1}"

export MYSQL_PWD="${GALERIA_ROOT_PASSWORD}"

# --- Discovery: resolve peers, find Synced node, set CLUSTER_ADDRESS / AM_I_BOOTSTRAP ---
SCRIPT_DIR="${SCRIPT_DIR:-/usr/local/bin}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/galera-discovery.sh"

# --- Write Galera config from template ---
"${SCRIPT_DIR}/galera-write-config.sh"

# --- Health check listener ---
socat -T 2 TCP-LISTEN:9200,reuseaddr,fork SYSTEM:"${SCRIPT_DIR}/galera-healthcheck.sh" 2>/dev/null &

# --- Init or clone data directory if empty ---
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
clone_enabled() { [ -n "${GALERIA_CLONE_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_CLONE_BACKUP_S3_BUCKET:-}" ]; }

if is_datadir_empty; then
  if clone_enabled; then
    log "Data directory empty and clone configured -> restoring from S3 backup..."
    "${SCRIPT_DIR}/galera-clone.sh"
  else
    log "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir="$DATA_DIR"
  fi
fi

if [ "$AM_I_BOOTSTRAP" = "1" ]; then
  GRASTATE="/var/lib/mysql/grastate.dat"
  if [ -f "$GRASTATE" ] && grep -q "safe_to_bootstrap: 0" "$GRASTATE"; then
    log "Setting safe_to_bootstrap=1 in grastate.dat"
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "$GRASTATE"
  fi
fi

# --- Start MariaDB (bootstrap or join) ---
if [ "$AM_I_BOOTSTRAP" = "1" ]; then
  log "Starting as new cluster (bootstrap)..."
  mariadbd --user=mysql --wsrep-new-cluster "$@" &
else
  log "Starting as cluster member (join)..."
  mariadbd --user=mysql "$@" &
fi
MYSQLD_PID=$!

# --- Wait for MariaDB ready ---
for _ in $(seq 1 60); do
  if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
done

if ! mariadb -u root -e "SELECT 1" &>/dev/null; then
  log "MariaDB did not become ready in time"
  kill "$MYSQLD_PID" 2>/dev/null || true
  exit 1
fi

# --- Ensure root@% exists ---
ROOT_SQL="CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${GALERIA_ROOT_PASSWORD}';
GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
mariadb -u root -e "$ROOT_SQL" 2>/dev/null || true

# --- Optional: schedule hot backups to S3 ---
if [ -n "${GALERIA_BACKUP_SCHEDULE:-}" ] && { [ -n "${GALERIA_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ]; }; then
  log "Enabling backup cron: $GALERIA_BACKUP_SCHEDULE"
  "${SCRIPT_DIR}/galera-backup-setup.sh"
fi

wait "$MYSQLD_PID"

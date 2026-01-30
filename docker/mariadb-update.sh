#!/bin/bash
# Safe MariaDB upgrade: run mariadb-upgrade when server is already running.
# Used when container starts with existing data from an older MariaDB version
# (e.g. 11.8 → 12.1). Idempotent: safe to run on fresh installs or already-upgraded data.
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

if ! command -v mariadb-upgrade &>/dev/null; then
  log "mariadb-upgrade not found, skipping upgrade step"
  exit 0
fi

export MYSQL_PWD="${GALERIA_ROOT_PASSWORD:-}"

# Server must be running. Try to connect (root may have no password on first bootstrap).
for _ in $(seq 1 30); do
  if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"${MYSQL_PWD}" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
done

if ! mariadb -u root -e "SELECT 1" &>/dev/null && ! mariadb -u root -p"${MYSQL_PWD}" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
  log "MariaDB not ready for mariadb-upgrade, skipping"
  exit 0
fi

log "Running mariadb-upgrade (system tables / upgrade check)..."
if mariadb-upgrade -u root; then
  log "mariadb-upgrade completed successfully"
else
  # Non-zero exit can mean "already up to date" or real failure; log but do not fail container
  log "mariadb-upgrade finished with exit code $? (may be already up to date)"
fi

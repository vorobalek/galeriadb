#!/usr/bin/env bash

version_major_minor() {
  local v="$1"
  echo "$v" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/' 2>/dev/null
}

version_compare() {
  local a="$1"
  local b="$2"
  if [ "$a" = "$b" ]; then
    echo 0
    return
  fi
  if [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" = "$a" ]; then
    echo -1
  else
    echo 1
  fi
}

if is_datadir_empty; then
  log "Auto-migrate: data directory empty -> skip"
else
  server_version=$(mariadb -u root -Nse "SELECT VERSION()" 2>/dev/null || true)
  if [ -z "${server_version:-}" ]; then
    log "Auto-migrate: unable to determine server version"
    exit 1
  fi
  server_mm=$(version_major_minor "$server_version")

  upgrade_info=""
  if [ -f "${DATA_DIR}/mysql_upgrade_info" ]; then
    upgrade_info=$(head -n 1 "${DATA_DIR}/mysql_upgrade_info" || true)
  elif [ -f "${DATA_DIR}/mariadb_upgrade_info" ]; then
    upgrade_info=$(head -n 1 "${DATA_DIR}/mariadb_upgrade_info" || true)
  fi
  data_mm=$(version_major_minor "$upgrade_info")

  needs_upgrade=0
  if [ -z "${data_mm:-}" ]; then
    needs_upgrade=1
  else
    cmp=$(version_compare "$data_mm" "$server_mm")
    if [ "$cmp" -lt 0 ]; then
      needs_upgrade=1
    elif [ "$cmp" -gt 0 ]; then
      log "Auto-migrate: data version ${data_mm} newer than server ${server_mm}; refusing to start"
      exit 1
    fi
  fi

  if [ "$needs_upgrade" -eq 0 ]; then
    log "Auto-migrate: data version ${data_mm} matches server ${server_mm} -> no upgrade needed"
  else
    log "Auto-migrate: data version ${data_mm:-unknown} -> server ${server_mm}; upgrade required"

    if backup_configured; then
      log "Auto-migrate: backup configured; waiting for Synced state"
      if ! wait_for_synced "${GALERIA_AUTO_MIGRATE_SYNC_TIMEOUT:-120}"; then
        log "Auto-migrate: node did not reach Synced state; refusing to migrate without backup"
        exit 1
      fi
      log "Auto-migrate: running pre-upgrade backup"
      /usr/local/bin/galera-backup.sh
      log "Auto-migrate: backup complete"
    else
      log "Auto-migrate: backup not configured; proceeding without backup"
    fi

    log "Auto-migrate: running mariadb-upgrade"
    mariadb-upgrade --user=root
    log "Auto-migrate: upgrade complete"
  fi
fi

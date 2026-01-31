#!/usr/bin/env bash

if is_datadir_empty; then
  if clone_enabled; then
    log "Data directory empty and clone configured -> restoring from S3 backup..."
    "${SCRIPT_DIR}/galera-clone.sh"
  else
    log "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir="$DATA_DIR"
  fi
fi

#!/usr/bin/env bash

MARIADB_LOGS_MODE="$(printf '%s' "${GALERIA_MARIADB_LOGS:-off}" | tr '[:upper:]' '[:lower:]')"
mariadbd_cmd=(mariadbd --user=mysql "$@")

if [ "${AM_I_BOOTSTRAP:-0}" = "1" ]; then
  log "Starting as new cluster (bootstrap)..."
  mariadbd_cmd=(mariadbd --user=mysql --wsrep-new-cluster "$@")
else
  log "Starting as cluster member (join)..."
fi

if [ "$MARIADB_LOGS_MODE" = "on" ]; then
  log "MariaDB/Galera logs to container stdout/stderr: enabled (GALERIA_MARIADB_LOGS=on)"
  "${mariadbd_cmd[@]}" &
else
  log "MariaDB/Galera logs to container stdout/stderr: disabled (set GALERIA_MARIADB_LOGS=on to enable)"
  "${mariadbd_cmd[@]}" >/tmp/galeria-mariadb.log 2>&1 &
fi

MYSQLD_PID=$!
export MYSQLD_PID

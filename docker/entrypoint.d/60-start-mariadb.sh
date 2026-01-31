#!/usr/bin/env bash

if [ "${AM_I_BOOTSTRAP:-0}" = "1" ]; then
  log "Starting as new cluster (bootstrap)..."
  mariadbd --user=mysql --wsrep-new-cluster "$@" &
else
  log "Starting as cluster member (join)..."
  mariadbd --user=mysql "$@" &
fi
MYSQLD_PID=$!
export MYSQLD_PID

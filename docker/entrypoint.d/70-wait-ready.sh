#!/usr/bin/env bash

if ! wait_for_mysql "${GALERIA_READY_TIMEOUT:-60}" "$MYSQLD_PID"; then
  log "MariaDB did not become ready in time (GALERIA_READY_TIMEOUT=${GALERIA_READY_TIMEOUT:-60}s, GALERIA_SST_TIMEOUT=${GALERIA_SST_TIMEOUT:-3600}s)"
  kill "$MYSQLD_PID" 2>/dev/null || true
  exit 1
fi

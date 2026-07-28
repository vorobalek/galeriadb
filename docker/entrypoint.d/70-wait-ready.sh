#!/usr/bin/env bash

if ! wait_for_mysql "${GALERIA_READY_TIMEOUT:-60}" "$MYSQLD_PID"; then
  log "MariaDB did not become ready in time (GALERIA_READY_TIMEOUT=${GALERIA_READY_TIMEOUT:-60}s, GALERIA_SST_TIMEOUT=${GALERIA_SST_TIMEOUT:-3600}s)"
  kill "$MYSQLD_PID" 2>/dev/null || true
  exit 1
fi

if [ "${AM_I_BOOTSTRAP:-0}" != "1" ] && [ "${SYNCED_PEER_FOUND:-0}" = "0" ]; then
  if ! wait_for_synced "${GALERIA_JOIN_PRIMARY_TIMEOUT:-30}"; then
    log "Non-candidate did not reach Synced state within ${GALERIA_JOIN_PRIMARY_TIMEOUT:-30}s; exiting for orchestrator restart"
    kill "$MYSQLD_PID" 2>/dev/null || true
    exit 1
  fi
fi

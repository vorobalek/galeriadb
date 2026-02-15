#!/usr/bin/env bash

if ! wait_for_mysql 60 "$MYSQLD_PID"; then
  log "MariaDB did not become ready in time"
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

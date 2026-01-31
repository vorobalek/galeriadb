#!/usr/bin/env bash

if ! wait_for_mysql; then
  log "MariaDB did not become ready in time"
  kill "$MYSQLD_PID" 2>/dev/null || true
  exit 1
fi

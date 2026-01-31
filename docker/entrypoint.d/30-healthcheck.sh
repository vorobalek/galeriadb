#!/usr/bin/env bash

socat -T 2 TCP-LISTEN:9200,reuseaddr,fork SYSTEM:"${SCRIPT_DIR}/galera-healthcheck.sh" 2>/dev/null &
sleep 2
code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 http://127.0.0.1:9200/ 2>/dev/null || echo '000')"
if [ "$code" = "000" ]; then
  log "ERROR: Healthcheck listener failed to start on port 9200"
  exit 1
fi
log "Healthcheck listener started on port 9200"

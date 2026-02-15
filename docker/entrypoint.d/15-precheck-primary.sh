#!/usr/bin/env bash

if [ "${AM_I_BOOTSTRAP:-0}" = "1" ] || [ "${SYNCED_PEER_FOUND:-0}" = "1" ]; then
  :
else
  timeout="${GALERIA_JOIN_PRIMARY_TIMEOUT:-30}"
  log "No Synced peer discovered for non-candidate; pre-checking primary availability for up to ${timeout}s before MariaDB start"

  deadline=$(($(date +%s) + timeout))
  precheck_synced_peer=""
  ips=""

  while [ "$(date +%s)" -lt "$deadline" ]; do
    ips="$(resolve_peers_ips || true)"
    if [ -n "$ips" ]; then
      if precheck_synced_peer="$(echo "$ips" | find_synced_peer 2>/dev/null)"; then
        break
      fi
    fi
    sleep "${GALERIA_DISCOVERY_INTERVAL:-1}"
  done

  if [ -z "$precheck_synced_peer" ]; then
    log "Non-candidate did not reach Synced state within ${timeout}s; exiting for orchestrator restart"
    exit 1
  fi

  SYNCED_PEER_FOUND=1
  CLUSTER_ADDRESS="gcomm://${precheck_synced_peer}:4567?pc.wait_prim=yes"
  export SYNCED_PEER_FOUND
  export CLUSTER_ADDRESS
  log "Pre-check found Synced peer at ${precheck_synced_peer}; proceeding to join"
fi

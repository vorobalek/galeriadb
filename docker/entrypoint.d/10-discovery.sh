#!/usr/bin/env bash

resolve_peers_ips() {
  for name in $(echo "$PEER_NAMES" | tr ',' ' '); do
    getent hosts "$name" 2>/dev/null | awk '{print $1}' || true
  done | sort -u
}

pick_local_ip_for_peer() {
  local peer_ip="$1"
  if [ -n "${GALERIA_NODE_ADDRESS:-}" ]; then
    echo "$GALERIA_NODE_ADDRESS"
    return 0
  fi
  local src
  src=$(ip route get "$peer_ip" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}')
  if [ -n "$src" ]; then
    echo "$src"
    return 0
  fi
  hostname -i 2>/dev/null | awk '{print $1}'
}

find_synced_peer() {
  local ip
  while read -r ip; do
    [ -z "$ip" ] && continue
    if mariadb -u root -h "$ip" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | grep -q "Synced"; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

PEER_NAMES="${GALERIA_PEERS}"
HOSTNAME="$(hostname)"
log "HOSTNAME=$HOSTNAME peers=$PEER_NAMES candidate=$GALERIA_BOOTSTRAP_CANDIDATE"

deadline=$(($(date +%s) + GALERIA_DISCOVERY_TIMEOUT))
SYNCED_PEER_IP=""
IPS=""

while [ "$(date +%s)" -lt "$deadline" ]; do
  IPS="$(resolve_peers_ips || true)"
  if [ -n "$IPS" ]; then
    if SYNCED_PEER_IP="$(echo "$IPS" | find_synced_peer 2>/dev/null)"; then
      break
    fi
  fi
  sleep "$GALERIA_DISCOVERY_INTERVAL"
done

log "Discovery finished: synced_peer=${SYNCED_PEER_IP:-none}, resolved_ips=${IPS:-none}"

FIRST_PEER_IP="$(echo "$IPS" | head -n 1 || true)"
if [ -z "$FIRST_PEER_IP" ]; then
  IP_ADDRESS="$(hostname -i 2>/dev/null | awk '{print $1}')"
else
  IP_ADDRESS="$(pick_local_ip_for_peer "$FIRST_PEER_IP")"
fi

if [ -z "${IP_ADDRESS:-}" ]; then
  log "Cannot determine own IP"
  exit 1
fi

export WSREP_CLUSTER_NAME="$GALERIA_CLUSTER_NAME"
export WSREP_NODE_NAME="$HOSTNAME"
export WSREP_NODE_ADDRESS="$IP_ADDRESS"

CLUSTER_ADDRESS=""
AM_I_BOOTSTRAP=0

if [ -n "$SYNCED_PEER_IP" ]; then
  log "Found existing Synced peer at $SYNCED_PEER_IP -> joining"
  CLUSTER_ADDRESS="gcomm://${SYNCED_PEER_IP}:4567?pc.wait_prim=yes"
else
  if [ "$HOSTNAME" = "$GALERIA_BOOTSTRAP_CANDIDATE" ]; then
    log "No existing cluster detected. I am bootstrap candidate -> bootstrapping"
    AM_I_BOOTSTRAP=1
    CLUSTER_ADDRESS="gcomm://"
  else
    CLUSTER_LIST=$(echo "$PEER_NAMES" | tr ',' '\n' | sed 's/$/:4567/' | tr '\n' ',' | sed 's/,$//')
    CLUSTER_ADDRESS="gcomm://${CLUSTER_LIST}?pc.wait_prim=yes"
    log "No existing cluster detected. Not a candidate -> joining and waiting primary: $CLUSTER_ADDRESS"
  fi
fi

export CLUSTER_ADDRESS
export AM_I_BOOTSTRAP

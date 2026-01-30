#!/bin/bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

: "${GALERIA_PEERS:?GALERIA_PEERS is required (e.g. tasks.galera)}"
: "${GALERIA_CLUSTER_NAME:=galera_cluster}"
: "${GALERIA_DISCOVERY_TIMEOUT:=25}"
: "${GALERIA_DISCOVERY_INTERVAL:=2}"
: "${GALERIA_BOOTSTRAP_CANDIDATE:=galera-node-a}"

export MYSQL_PWD="${GALERIA_ROOT_PASSWORD:-mariadb}"
PEER_NAMES="${GALERIA_PEERS}"

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

HOSTNAME="$(hostname)"
log "HOSTNAME=$HOSTNAME peers=$PEER_NAMES candidate=$GALERIA_BOOTSTRAP_CANDIDATE"

deadline=$(( $(date +%s) + GALERIA_DISCOVERY_TIMEOUT ))
SYNCED_PEER_IP=""

while [ $(date +%s) -lt "$deadline" ]; do
  IPS="$(resolve_peers_ips || true)"
  if [ -n "$IPS" ]; then
    if SYNCED_PEER_IP="$(echo "$IPS" | find_synced_peer 2>/dev/null)"; then
      break
    fi
  fi
  sleep "$GALERIA_DISCOVERY_INTERVAL"
done

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

export CLUSTER_ADDRESS=""
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
    # Non-candidate: never bootstrap, only join and wait for primary
    CLUSTER_LIST=$(echo "$PEER_NAMES" | tr ',' '\n' | sed 's/$/:4567/' | tr '\n' ',' | sed 's/,$//')
    CLUSTER_ADDRESS="gcomm://${CLUSTER_LIST}?pc.wait_prim=yes"
    log "No existing cluster detected. Not a candidate -> joining and waiting primary: $CLUSTER_ADDRESS"
  fi
fi

GALERA_CNF="/etc/mysql/mariadb.conf.d/99-galera.cnf"
cp /etc/mysql/conf.d/galera.cnf.template "$GALERA_CNF"
for var in CLUSTER_ADDRESS WSREP_CLUSTER_NAME WSREP_NODE_NAME WSREP_NODE_ADDRESS; do
  val="${!var}"
  [ -z "$val" ] && continue
  val_escaped=$(echo "$val" | sed 's/#/\\#/g; s#/#\\/#g; s#&#\\&#g')
  sed -i "s#{{${var}}}#${val_escaped}#g" "$GALERA_CNF"
done
chmod 660 "$GALERA_CNF"
chown mysql:mysql "$GALERA_CNF"

log "============ galera.cnf ============"
cat "$GALERA_CNF"
log "===================================="

socat -T 2 TCP-LISTEN:9200,reuseaddr,fork SYSTEM:"/usr/local/bin/galera-healthcheck.sh" 2>/dev/null &

if [ ! -f /var/lib/mysql/ibdata1 ]; then
  log "Initializing MariaDB data directory..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql
fi

if [ "$AM_I_BOOTSTRAP" = "1" ]; then
  GRASTATE="/var/lib/mysql/grastate.dat"
  if [ -f "$GRASTATE" ] && grep -q "safe_to_bootstrap: 0" "$GRASTATE"; then
    log "Setting safe_to_bootstrap=1 in grastate.dat"
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "$GRASTATE"
  fi
fi

if [ "$AM_I_BOOTSTRAP" = "1" ]; then
  log "Starting as new cluster (bootstrap)..."
  mariadbd --user=mysql --wsrep-new-cluster "$@" &
else
  log "Starting as cluster member (join)..."
  mariadbd --user=mysql "$@" &
fi
MYSQLD_PID=$!

for i in $(seq 1 60); do
  if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
done

if ! mariadb -u root -e "SELECT 1" &>/dev/null; then
  log "MariaDB did not become ready in time"
  kill "$MYSQLD_PID" 2>/dev/null || true
  exit 1
fi

ROOT_SQL="CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${GALERIA_ROOT_PASSWORD:-mariadb}';
GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
mariadb -u root -e "$ROOT_SQL" 2>/dev/null || true

wait "$MYSQLD_PID"
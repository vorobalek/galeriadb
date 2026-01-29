#!/bin/bash
set -e

# Bootstrap logic: any node can start first. One node must run new-cluster (bootstrap),
# others join. We pick bootstrap candidate by lexicographically smallest hostname.
# Bootstrap candidate bootstraps only if no peer is already in the cluster (Synced).

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-mariadb}"

# Resolve peer list: Docker Swarm uses tasks.$SERVICE_NAME, Compose uses GALERA_PEERS
if [ -n "${GALERA_PEERS}" ]; then
    # Compose: GALERA_PEERS=galera1,galera2,galera3
    PEER_NAMES="${GALERA_PEERS}"
else
    # Swarm: SERVICE_NAME=mariadb -> tasks.mariadb
    SERVICE_NAME="${SERVICE_NAME:-mariadb}"
    PEER_NAMES=$(getent hosts "tasks.${SERVICE_NAME}" 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [ -z "$PEER_NAMES" ]; then
        PEER_NAMES="${HOSTNAME}"
    fi
fi

# Get all peer IPs (and self)
ALL_HOSTS=""
for name in $(echo "$PEER_NAMES" | tr ',' ' '); do
    ip=$(getent hosts "$name" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -n "$ip" ]; then
        ALL_HOSTS="${ALL_HOSTS} ${ip}"
    fi
done
ALL_HOSTS=$(echo "$ALL_HOSTS" | xargs)

export IP_ADDRESS=$(getent hosts "$HOSTNAME" 2>/dev/null | awk '{print $1}' | head -1)
if [ -z "$IP_ADDRESS" ]; then
    export IP_ADDRESS=$(hostname -i 2>/dev/null | awk '{print $1}')
fi
if [ -z "$IP_ADDRESS" ]; then
    echo "Cannot determine own IP"
    exit 1
fi

# Wait until we see enough peers (optional: CLUSTER_NODES for quorum)
CLUSTER_NODES=${CLUSTER_NODES:-3}
peer_count=$(echo "$ALL_HOSTS" | wc -w)
echo "Peers resolved: $peer_count - $ALL_HOSTS"

# Bootstrap candidate: node with lexicographically smallest hostname among peers
PEER_HOSTNAMES=$(echo "$PEER_NAMES" | tr ',' '\n' | sort -u)
BOOTSTRAP_CANDIDATE=$(echo "$PEER_HOSTNAMES" | head -1)
export CLUSTER_ADDRESS=""

# Am I the bootstrap candidate?
if [ "$HOSTNAME" = "$BOOTSTRAP_CANDIDATE" ]; then
    echo "I am bootstrap candidate ($HOSTNAME). Checking if cluster already exists..."
    for ip in $ALL_HOSTS; do
        [ "$ip" = "$IP_ADDRESS" ] && continue
        if mariadb -u root -h "$ip" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | grep -q "Synced"; then
            echo "Found existing cluster at $ip - joining."
            export CLUSTER_ADDRESS="gcomm://${ip}:4567?pc.wait_prim=yes"
            break
        fi
    done
    if [ -z "$CLUSTER_ADDRESS" ]; then
        echo "No cluster found. Bootstrapping new cluster."
        export CLUSTER_ADDRESS="gcomm://"
    fi
else
    # Join: use fixed list of peer hostnames (not resolved IPs), so every node has the same
    # full list regardless of startup order. Galera resolves hostnames at connect time.
    # In Swarm/Compose there is no guarantee which node starts first.
    CLUSTER_LIST=$(echo "$PEER_NAMES" | tr ',' '\n' | sed 's/$/:4567/' | tr '\n' ',' | sed 's/,$//')
    export CLUSTER_ADDRESS="gcomm://${CLUSTER_LIST}?pc.wait_prim=yes"
    echo "Joining cluster: $CLUSTER_ADDRESS"
fi

# Build galera.cnf from template
export WSREP_CLUSTER_NAME="${WSREP_CLUSTER_NAME:-galera_cluster}"
export WSREP_NODE_NAME="${HOSTNAME}"
export WSREP_NODE_ADDRESS="${IP_ADDRESS}"

# Write to mariadb.conf.d/99-galera.cnf so it loads AFTER 50-server.cnf (which sets bind-address=127.0.0.1)
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

echo "============ galera.cnf ============"
cat "$GALERA_CNF"
echo "===================================="

# Start health check listener in background (for HAProxy)
socat TCP-LISTEN:9200,reuseaddr,fork SYSTEM:"/usr/local/bin/galera-healthcheck.sh" &
SOCAT_PID=$!

# Initialize data dir if empty (first run)
if [ ! -f /var/lib/mysql/ibdata1 ]; then
    echo "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql
fi

# When bootstrapping: allow force bootstrap if no other node is Synced (e.g. after full cluster shutdown).
# Galera refuses to bootstrap when grastate.dat has safe_to_bootstrap: 0; set to 1 so we can form a new primary.
if [ "$CLUSTER_ADDRESS" = "gcomm://" ]; then
    GRASTATE="/var/lib/mysql/grastate.dat"
    if [ -f "$GRASTATE" ] && grep -q "safe_to_bootstrap: 0" "$GRASTATE"; then
        echo "Setting safe_to_bootstrap=1 in grastate.dat (no Synced peers; forcing bootstrap)."
        sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "$GRASTATE"
    fi
fi

# Start MariaDB in background so we can ensure root@'%' exists for remote (HAProxy) connections
if [ "$CLUSTER_ADDRESS" = "gcomm://" ]; then
    echo "Starting as new cluster (bootstrap)..."
    mariadbd --user=mysql --wsrep-new-cluster "$@" &
else
    echo "Starting as cluster member (join)..."
    mariadbd --user=mysql "$@" &
fi
MYSQLD_PID=$!

# Wait for MariaDB to accept connections (socket first, then TCP)
wait_for_mysql() {
    local i=0
    while [ $i -lt 60 ]; do
        if mariadb -u root -e "SELECT 1" &>/dev/null || mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "SELECT 1" &>/dev/null; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}
if ! wait_for_mysql; then
    echo "MariaDB did not become ready in time"
    kill $MYSQLD_PID 2>/dev/null || true
    exit 1
fi

# Ensure root can connect from any host (for HAProxy and clients)
mariadb -u root -p"$MYSQL_PWD" -h 127.0.0.1 -e "
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD:-mariadb}';
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null || mariadb -u root -e "
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD:-mariadb}';
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null || true

wait $MYSQLD_PID

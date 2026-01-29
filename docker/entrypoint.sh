#!/bin/bash
set -e

# Bootstrap logic: any node can start first. One node must run new-cluster (bootstrap),
# others join. We pick bootstrap candidate by lexicographically smallest hostname.
# Bootstrap candidate bootstraps only if no peer is already in the cluster (Synced).

export MYSQL_PWD="${GALERIA_ROOT_PASSWORD:-mariadb}"

# Peer list from GALERIA_PEERS only (Compose service names, Swarm task names, or IPs/hostnames).
# Examples: galera1,galera2,galera3  or  tasks.galera  or  10.0.0.1,10.0.0.2,10.0.0.3
if [ -n "${GALERIA_PEERS}" ]; then
    PEER_NAMES="${GALERIA_PEERS}"
else
    PEER_NAMES="${HOSTNAME}"
fi

# Resolve own IP first (needed for "only self" check)
export IP_ADDRESS=$(getent hosts "$HOSTNAME" 2>/dev/null | awk '{print $1}' | head -1)
if [ -z "$IP_ADDRESS" ]; then
    export IP_ADDRESS=$(hostname -i 2>/dev/null | awk '{print $1}')
fi
if [ -z "$IP_ADDRESS" ]; then
    echo "Cannot determine own IP"
    exit 1
fi

# Resolve peers; in Swarm/K8s DNS may not be ready at startup (tasks.galera = 0 until tasks register).
# Retry a few times so we don't bootstrap too eagerly when DNS is just slow.
resolve_peers() {
    for name in $(echo "$PEER_NAMES" | tr ',' ' '); do
        getent hosts "$name" 2>/dev/null | awk '{print $1}'
    done | sort -u | tr '\n' ' ' | xargs
}
ALL_HOSTS=$(resolve_peers)
GALERIA_RESOLVE_RETRIES=${GALERIA_RESOLVE_RETRIES:-6}
GALERIA_RESOLVE_INTERVAL=${GALERIA_RESOLVE_INTERVAL:-5}
retry=0
while [ $retry -lt "$GALERIA_RESOLVE_RETRIES" ]; do
    peer_count=$(echo "$ALL_HOSTS" | wc -w)
    # Proceed when we see at least 2 IPs (so at least one other node is in DNS); otherwise retry
    if [ $peer_count -ge 2 ]; then
        break
    fi
    retry=$((retry + 1))
    echo "Peers resolved: $peer_count (Swarm/K8s DNS may not be ready); retry $retry/$GALERIA_RESOLVE_RETRIES in ${GALERIA_RESOLVE_INTERVAL}s..."
    sleep "$GALERIA_RESOLVE_INTERVAL"
    ALL_HOSTS=$(resolve_peers)
done

peer_count=$(echo "$ALL_HOSTS" | wc -w)
echo "Peers resolved: $peer_count - $ALL_HOSTS"

# If no peers resolved (or only self): we are the first node (Swarm/K8s DNS not ready yet). Bootstrap.
# This breaks the deadlock where every task waits for others to appear in DNS.
ONLY_SELF_OR_EMPTY=0
if [ $peer_count -eq 0 ]; then
    ONLY_SELF_OR_EMPTY=1
else
    other_peers=$(echo "$ALL_HOSTS" | tr ' ' '\n' | grep -v "^${IP_ADDRESS}$" | tr '\n' ' ' | xargs)
    [ -z "$other_peers" ] && ONLY_SELF_OR_EMPTY=1
fi

PEER_HOSTNAMES=$(echo "$PEER_NAMES" | tr ',' '\n' | sort -u)
export CLUSTER_ADDRESS=""
AM_I_BOOTSTRAP=0

if [ "$ONLY_SELF_OR_EMPTY" = 1 ]; then
    echo "No other peers resolved (Swarm/K8s: DNS not ready yet). Acting as first node (bootstrap)."
    AM_I_BOOTSTRAP=1
elif echo "$PEER_NAMES" | tr ',' '\n' | grep -qFx "$HOSTNAME"; then
    BOOTSTRAP_CANDIDATE=$(echo "$PEER_HOSTNAMES" | head -1)
    [ "$HOSTNAME" = "$BOOTSTRAP_CANDIDATE" ] && AM_I_BOOTSTRAP=1
else
    SMALLEST_IP=$(echo "$ALL_HOSTS" | tr ' ' '\n' | sort -V | head -1)
    [ "$IP_ADDRESS" = "$SMALLEST_IP" ] && AM_I_BOOTSTRAP=1
fi

if [ "$AM_I_BOOTSTRAP" = 1 ]; then
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

# Build galera.cnf from template (GALERIA_CLUSTER_NAME = Galera wsrep_cluster_name; nodes with same name form one cluster)
export WSREP_CLUSTER_NAME="${GALERIA_CLUSTER_NAME:-galera_cluster}"
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
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${GALERIA_ROOT_PASSWORD:-mariadb}';
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null || mariadb -u root -e "
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${GALERIA_ROOT_PASSWORD:-mariadb}';
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null || true

wait $MYSQLD_PID

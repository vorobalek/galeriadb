#!/usr/bin/env bash
log "Case 05.consensus: 3-node cluster with consensus bootstrap (no static candidate)"

# Use a separate compose file and project for consensus test
CONSENSUS_COMPOSE="${SCRIPT_DIR}/compose/compose.consensus.yml"
CONSENSUS_PROJECT="galeriadb-consensus-test"

docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" down -v --remove-orphans 2>/dev/null || true
docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" up -d

log "Waiting for Galera cluster size=3 via consensus (up to 180s)..."
elapsed=0
while [ "$elapsed" -lt 180 ]; do
  size=$(docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera1 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
  if [ "${size:-0}" = "3" ]; then
    log "wsrep_cluster_size=3"
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if [ "${size:-0}" != "3" ]; then
  log "Cluster did not reach size 3 (got ${size:-0})"
  logdump "$CONSENSUS_COMPOSE" "$CONSENSUS_PROJECT"
  docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" down -v --remove-orphans 2>/dev/null || true
  exit 1
fi

log "Waiting for galera1 Synced (up to 60s)..."
elapsed=0
while [ "$elapsed" -lt 60 ]; do
  ready=$(docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera1 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_ready'" 2>/dev/null | awk '{print $2}' || echo "")
  state=$(docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera1 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
  if [ "$ready" = "ON" ] && [ "$state" = "Synced" ]; then
    log "galera1 is Synced"
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if [ "$ready" != "ON" ] || [ "$state" != "Synced" ]; then
  log "galera1 did not reach Synced: ready=$ready state=$state"
  logdump "$CONSENSUS_COMPOSE" "$CONSENSUS_PROJECT"
  docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" down -v --remove-orphans 2>/dev/null || true
  exit 1
fi

log "Testing replication across consensus cluster..."
docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera1 \
  mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS consensus_test; CREATE TABLE consensus_test (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO consensus_test VALUES (1, 'consensus_ok');"

v2="" v3=""
for attempt in {1..30}; do
  v2=$(docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera2 \
    mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM consensus_test WHERE id=1" 2>/dev/null || echo "")
  v3=$(docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" exec -T galera3 \
    mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM consensus_test WHERE id=1" 2>/dev/null || echo "")
  if [ "$v2" = "consensus_ok" ] && [ "$v3" = "consensus_ok" ]; then
    break
  fi
  [ "$attempt" -lt 30 ] && sleep 1
done
if [ "$v2" != "consensus_ok" ] || [ "$v3" != "consensus_ok" ]; then
  log "Replication failed: galera2='$v2' galera3='$v3'"
  logdump "$CONSENSUS_COMPOSE" "$CONSENSUS_PROJECT"
  docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" down -v --remove-orphans 2>/dev/null || true
  exit 1
fi
log "Replication OK across all 3 nodes"

docker compose -f "$CONSENSUS_COMPOSE" -p "$CONSENSUS_PROJECT" down -v --remove-orphans 2>/dev/null || true
log "Case 05.consensus passed."

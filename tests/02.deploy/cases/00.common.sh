#!/usr/bin/env bash
# Common vars and helpers for deploy cases. Source from entrypoint.
# Expects: COMPOSE_FILE, PROJECT_NAME, PASS, IMAGE (set by entrypoint).

# Poll until galera1 accepts MySQL (e.g. after bootstrap). No fixed sleep.
wait_galera1_ready() {
  local elapsed=0
  log "Waiting for galera1 MySQL (up to 60s)..."
  while [ "$elapsed" -lt 60 ]; do
    if docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
      mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
      log "galera1 MySQL ready"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "galera1 did not become ready in time"
  return 1
}

wait_cluster_3() {
  local elapsed=0
  log "Waiting for Galera cluster size=3 (up to 120s)..."
  while [ "$elapsed" -lt 120 ]; do
    local size
    size=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
      mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
    if [ "${size:-0}" = "3" ]; then
      log "wsrep_cluster_size=3"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  size=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
  log "Cluster size did not reach 3 (got $size)"
  return 1
}

wait_synced() {
  local elapsed=0
  log "Waiting for galera1 Synced (up to 60s)..."
  while [ "$elapsed" -lt 60 ]; do
    local ready state
    ready=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
      mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_ready'" 2>/dev/null | awk '{print $2}' || echo "")
    state=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
      mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$ready" = "ON" ] && [ "$state" = "Synced" ]; then
      log "galera1 is Synced"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "Node not ready: wsrep_ready=$ready wsrep_local_state_comment=$state"
  return 1
}

create_and_check_replication() {
  log "Creating test table on galera1..."
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
    mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_test; CREATE TABLE ci_test (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_test VALUES (1, 'from_node1');"
  log "Reading from galera2 and galera3 (poll until replicated)..."
  local v2 v3 attempt
  for attempt in 1 2 3 4 5; do
    v2=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera2 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
    v3=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera3 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
    if [ "$v2" = "from_node1" ] && [ "$v3" = "from_node1" ]; then
      break
    fi
    [ "$attempt" -lt 5 ] && sleep 1
  done
  if [ "$v2" != "from_node1" ] || [ "$v3" != "from_node1" ]; then
    log "Replication check failed: galera2='$v2' galera3='$v3'"
    return 1
  fi
  return 0
}

check_haproxy() {
  log "Checking HAProxy endpoint (poll up to 20s)..."
  local v_haproxy elapsed=0
  while [ "$elapsed" -lt 20 ]; do
    v_haproxy=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" run --rm -T --no-deps --entrypoint mariadb galera1 \
      -h haproxy -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
    if [ "$v_haproxy" = "from_node1" ]; then
      log "HAProxy OK"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "HAProxy read failed: got '$v_haproxy'"
  return 1
}

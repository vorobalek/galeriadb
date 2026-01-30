#!/usr/bin/env bash
# Case: start cluster, init, create data; stop all nodes; start again — cluster must reassemble and data persist.
# Sourced from entrypoint. Uses COMPOSE_FILE, PROJECT_NAME, PASS from 00.common.sh.

log "Case 04.full-restart: full stop/start, cluster reassembly"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d

wait_cluster_3 || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}
wait_synced || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}
create_and_check_replication || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}
check_haproxy || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

log "Stopping all Galera nodes and HAProxy..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" stop galera1 galera2 galera3 haproxy

log "Starting all services again..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" start galera1 galera2 galera3 haproxy

log "Waiting for cluster to reassemble (up to 120s)..."
wait_cluster_3 || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}
wait_synced || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

log "Verifying data persisted after full restart (poll up to 30s)..."
v1="" v2="" v3=""
for attempt in {1..30}; do
  v1=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  v2=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera2 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  v3=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera3 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  if [ "$v1" = "from_node1" ] && [ "$v2" = "from_node1" ] && [ "$v3" = "from_node1" ]; then
    log "Data verified on all nodes"
    break
  fi
  [ "$attempt" -lt 30 ] && sleep 1
done
if [ "$v1" != "from_node1" ] || [ "$v2" != "from_node1" ] || [ "$v3" != "from_node1" ]; then
  log "Data check failed after full restart: galera1='$v1' galera2='$v2' galera3='$v3'"
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
fi
check_haproxy || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

log "Case 04.full-restart passed."

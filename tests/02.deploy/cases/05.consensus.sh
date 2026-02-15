#!/usr/bin/env bash
log "Case 05.consensus: non-candidate must not bootstrap without primary"

docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true

log "Starting non-candidate node galera2 only..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d galera2

log "Ensuring galera2 does not self-bootstrap and gets auto-restarted (observe up to 40s)..."
elapsed=0
while [ "$elapsed" -lt 40 ]; do
  state="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera2 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")"
  size="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera2 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")"

  if [ "$state" = "Synced" ] && [ "$size" = "1" ]; then
    log "galera2 unexpectedly self-bootstrapped: wsrep_local_state_comment=$state wsrep_cluster_size=$size"
    logdump "$COMPOSE_FILE" "$PROJECT_NAME"
    exit 1
  fi

  sleep 1
  elapsed=$((elapsed + 1))
done

galera2_cid="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps -q galera2)"
restart_count="$(docker inspect -f '{{.RestartCount}}' "$galera2_cid" 2>/dev/null || echo 0)"
if [ "${restart_count:-0}" -lt 1 ]; then
  log "galera2 did not auto-restart while primary was unavailable (RestartCount=$restart_count)"
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
fi
log "galera2 auto-restart observed (RestartCount=$restart_count)"

log "Starting bootstrap candidate and one additional node..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d galera1 galera3

log "Primary is available; waiting for auto-restarted galera2 to join..."

log "Starting HAProxy after all database nodes are up..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d haproxy

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

log "Case 05.consensus passed."

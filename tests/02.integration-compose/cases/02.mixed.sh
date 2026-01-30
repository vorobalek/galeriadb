# Case: start galera1, then galera2/galera3 after delay, then HAProxy.
# Sourced from entrypoint. Uses COMPOSE_FILE, PROJECT_NAME, PASS from 00.common.sh.

log "Case 02.mixed: staggered start"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d galera1
sleep 25
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d galera2 galera3
sleep 5
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d haproxy

wait_cluster_3 || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
wait_synced || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
create_and_check_replication || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
check_haproxy || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
log "Case 02.mixed passed."

#!/usr/bin/env bash
log "Case 01.all: start all at once"
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
log "Case 01.all passed."

# Case: start all, replication + HAProxy, then restart galera2 and verify cluster.
# Sourced from entrypoint. Uses COMPOSE_FILE, PROJECT_NAME, PASS from 00.common.sh.

log "Case 03.restart: restart node and verify"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d

wait_cluster_3 || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
wait_synced || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
create_and_check_replication || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }
check_haproxy || { logdump "$COMPOSE_FILE" "$PROJECT_NAME"; exit 1; }

log "Restarting galera2..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" restart galera2
log "Waiting for galera2 to rejoin (up to 90s)..."
elapsed=0
while [ "$elapsed" -lt 90 ]; do
  size2=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
    mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
  if [ "$size2" = "3" ]; then
    log "Cluster size=3 after restart"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
size2=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
  mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
if [ "$size2" != "3" ]; then
  log "After restart: cluster size=$size2 (expected 3)"
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
fi
log "Case 03.restart passed."

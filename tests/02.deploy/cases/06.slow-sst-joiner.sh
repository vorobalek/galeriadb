#!/usr/bin/env bash
# Regression test for the failure reported in issue #27: a non-candidate whose
# state transfer takes longer than the container's own timeouts is destroyed
# while the transfer is still running - by its entrypoint (readiness timeout) or
# by the orchestrator (health check reporting unhealthy, which makes Swarm
# restart the task). Everything here is asserted on behavior with default
# settings: the joiner must survive, join and serve, the transfer must really be
# slow, and neither node may be reported unhealthy while it transfers state.

log "Case 06.slow-sst-joiner: a node surviving a state transfer longer than its timeouts"

SLOW_IMAGE="galeriadb/test-slow-sst:local"
JOINER="${PROJECT_NAME}-galera4"
SST_DELAY=150

cleanup_joiner() {
  docker rm -fv "$JOINER" >/dev/null 2>&1 || true
}

joiner_failed() {
  log "$1"
  log "--- joiner log (tail) ---"
  docker logs "$JOINER" 2>&1 | tail -30
  cleanup_joiner
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d galera1

wait_synced || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

log "Building $SLOW_IMAGE from $IMAGE (joiner transfer delayed by ${SST_DELAY}s)..."
docker build -q \
  --build-arg BASE_IMAGE="$IMAGE" \
  -t "$SLOW_IMAGE" \
  "${SCRIPT_DIR}/slow-sst" >/dev/null

JOINER_NET="$(docker network ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "name=galera_net" --format '{{.Name}}' | head -n1)"
JOINER_NET="${JOINER_NET:-${PROJECT_NAME}_galera_net}"

cleanup_joiner

# Default timeouts on purpose: this is the reported configuration.
log "Starting joiner galera4 with default settings on network $JOINER_NET..."
docker run -d \
  --name "$JOINER" \
  --hostname galera4 \
  --network "$JOINER_NET" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1,galera2,galera3 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e FAKE_SST_DELAY="$SST_DELAY" \
  "$SLOW_IMAGE" >/dev/null

start_ts="$(date +%s)"
ready_after=""
elapsed=0
while [ "$elapsed" -lt 420 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$JOINER" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    joiner_failed "Joiner exited after ${elapsed}s while its state transfer was still running (exit code $(docker inspect --format '{{.State.ExitCode}}' "$JOINER" 2>/dev/null || echo unknown))"
  fi

  # An unhealthy verdict is what makes Swarm restart a task, so it counts as a
  # failure even though this test runs under Compose.
  joiner_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$JOINER" 2>/dev/null || echo "none")"
  if [ "$joiner_health" = "unhealthy" ]; then
    joiner_failed "Joiner was reported unhealthy after ${elapsed}s while receiving its state transfer"
  fi

  donor_id="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps -q galera1 2>/dev/null)"
  donor_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$donor_id" 2>/dev/null || echo "none")"
  if [ "$donor_health" = "unhealthy" ]; then
    joiner_failed "Donor galera1 was reported unhealthy after ${elapsed}s while serving the state transfer"
  fi

  if docker exec "$JOINER" mariadb -u root -p"$PASS" -e "SELECT 1" >/dev/null 2>&1; then
    ready_after="$(($(date +%s) - start_ts))"
    log "Joiner accepts connections after ${ready_after}s"
    break
  fi

  sleep 2
  elapsed=$((elapsed + 2))
done

if [ -z "$ready_after" ]; then
  joiner_failed "Joiner never accepted connections"
fi

# Guard the reproduction itself: if the transfer finished quickly, the case would
# pass without ever exercising the reported failure.
if [ "$ready_after" -lt 60 ]; then
  joiner_failed "Joiner became ready after only ${ready_after}s; the transfer was not slower than the timeouts, so this case proves nothing"
fi

log "Waiting for the joiner to reach Synced (up to 60s)..."
elapsed=0
state=""
while [ "$elapsed" -lt 60 ]; do
  state="$(docker exec "$JOINER" mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")"
  [ "$state" = "Synced" ] && break
  sleep 2
  elapsed=$((elapsed + 2))
done
if [ "$state" != "Synced" ]; then
  joiner_failed "Joiner did not reach Synced (state=${state:-none})"
fi

size="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
  mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")"
if [ "${size:-0}" != "2" ]; then
  joiner_failed "Donor reports wsrep_cluster_size=$size (expected 2)"
fi

log "Transferred state for ${ready_after}s without either node being destroyed; cluster size 2"
cleanup_joiner

log "Case 06.slow-sst-joiner passed."

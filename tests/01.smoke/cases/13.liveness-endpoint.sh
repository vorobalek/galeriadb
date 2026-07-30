#!/usr/bin/env bash
set -euo pipefail

log "Case 13.liveness-endpoint: /liveness stays 200 during a state transfer while / reports not ready"

docker rm -fv "$CONTAINER_NAME" 2>/dev/null || true

# Part 1: endpoint verdicts with no server running, driven directly through the
# health script (the same way socat feeds it a request).
unit_rc=0
docker run --rm -i --entrypoint bash "$IMAGE" -s <<'INNER' || unit_rc=$?
set -euo pipefail
cd /usr/local/bin
# shellcheck source=/dev/null
source ./common.sh
export GALERIA_ROOT_PASSWORD="unused"

ask() { printf 'GET %s HTTP/1.0\r\n\r\n' "$1" | ./galera-http-health.sh | head -n1; }

# No server and no transfer: both endpoints must report a problem.
readiness="$(ask /)"
liveness="$(ask /liveness)"
case "$readiness" in
  *"503"*) echo "OK: / is 503 with no server" ;;
  *) echo "FAIL: expected 503 from / with no server, got: $readiness"; exit 1 ;;
esac
case "$liveness" in
  *"503"*) echo "OK: /liveness is 503 with no server and no transfer" ;;
  *) echo "FAIL: expected 503 from /liveness with no server, got: $liveness"; exit 1 ;;
esac

# A state transfer in progress: the node is not ready, but it must stay alive.
(exec -a "/usr/bin/wsrep_sst_rsync --role joiner" sleep 30) &
FAKE_PID=$!
waited=0
while [ "$waited" -lt 10 ]; do
  sst_in_progress && break
  sleep 0.2
  waited=$((waited + 1))
done
if ! sst_in_progress; then
  echo "FAIL: fake state transfer was not detected"
  kill "$FAKE_PID" 2>/dev/null || true
  exit 1
fi

readiness="$(ask /)"
liveness="$(ask /liveness)"
kill "$FAKE_PID" 2>/dev/null || true
wait "$FAKE_PID" 2>/dev/null || true

case "$readiness" in
  *"503"*) echo "OK: / stays 503 during a state transfer" ;;
  *) echo "FAIL: expected 503 from / during a transfer, got: $readiness"; exit 1 ;;
esac
case "$liveness" in
  *"200"*) echo "OK: /liveness is 200 during a state transfer" ;;
  *) echo "FAIL: expected 200 from /liveness during a transfer, got: $liveness"; exit 1 ;;
esac
INNER

if [ "$unit_rc" -ne 0 ]; then
  log "FAIL: health endpoints did not behave as expected inside the image"
  exit 1
fi

# Part 2: a running node answers both endpoints and reports healthy to Docker.
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE" >/dev/null

elapsed=0
code=""
while [ "$elapsed" -lt 90 ]; do
  code="$(docker exec "$CONTAINER_NAME" curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:9200/ 2>/dev/null || echo "000")"
  [ "$code" = "200" ] && break
  sleep 2
  elapsed=$((elapsed + 2))
done
if [ "$code" != "200" ]; then
  log "FAIL: readiness endpoint did not return 200 on a bootstrapped node (got $code)"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -40
  exit 1
fi

code="$(docker exec "$CONTAINER_NAME" curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:9200/liveness 2>/dev/null || echo "000")"
if [ "$code" != "200" ]; then
  log "FAIL: liveness endpoint did not return 200 on a Synced node (got $code)"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -40
  exit 1
fi

status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
elapsed=0
while [ "$elapsed" -lt 40 ] && [ "$status" != "healthy" ]; do
  sleep 2
  elapsed=$((elapsed + 2))
  status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")"
done
if [ "$status" != "healthy" ]; then
  log "FAIL: expected Docker health status 'healthy' with the liveness check, got '$status'"
  docker inspect --format '{{json .State.Health}}' "$CONTAINER_NAME" 2>&1 | tail -5
  exit 1
fi

docker rm -fv "$CONTAINER_NAME" >/dev/null 2>&1 || true

log "Case 13.liveness-endpoint passed."

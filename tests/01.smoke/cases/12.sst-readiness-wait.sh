#!/usr/bin/env bash
set -euo pipefail

log "Case 12.sst-readiness-wait: readiness timeout is paused while a state transfer runs"

docker rm -fv "$CONTAINER_NAME" 2>/dev/null || true

# Part 1: wait_for_mysql semantics, exercised directly in the image.
# A fake wsrep_sst_* process stands in for a real joiner transfer, so the case
# stays deterministic and does not need a second node.
unit_rc=0
docker run --rm -i --entrypoint bash "$IMAGE" -s <<'INNER' || unit_rc=$?
set -euo pipefail
cd /usr/local/bin
# shellcheck source=/dev/null
source ./entrypoint-lib.sh

export MYSQL_PWD="unused"
FAKE_PID=""

start_fake_sst() {
  (exec -a "/usr/bin/wsrep_sst_rsync --role joiner" sleep "$1") &
  FAKE_PID=$!
  local waited=0
  while [ "$waited" -lt 10 ]; do
    sst_in_progress && return 0
    sleep 0.2
    waited=$((waited + 1))
  done
  echo "FAIL: fake SST process was not detected by sst_in_progress"
  return 1
}

stop_fake_sst() {
  [ -n "$FAKE_PID" ] || return 0
  kill "$FAKE_PID" 2>/dev/null || true
  wait "$FAKE_PID" 2>/dev/null || true
  FAKE_PID=""
}

# Prints "<rc> <seconds>"; wait_for_mysql logs go to a file to keep stdout clean.
run_wait() {
  local timeout="$1" start rc=0
  start=$(date +%s)
  wait_for_mysql "$timeout" "" >/tmp/wait-for-mysql.log 2>&1 || rc=$?
  echo "$rc $(($(date +%s) - start))"
}

# 1. No transfer running: fail fast at the configured timeout (old behavior).
read -r rc secs < <(run_wait 3)
if [ "$rc" != "1" ] || [ "$secs" -gt 10 ]; then
  echo "FAIL: without SST expected rc=1 after ~3s, got rc=$rc after ${secs}s"
  exit 1
fi
echo "OK: without SST the readiness wait still fails fast (${secs}s)"

# 2. Transfer running: the timeout is paused, and restarts once SST ends.
start_fake_sst 8
export GALERIA_SST_TIMEOUT=60
read -r rc secs < <(run_wait 3)
stop_fake_sst
if [ "$rc" != "1" ] || [ "$secs" -lt 9 ]; then
  echo "FAIL: with an 8s SST expected rc=1 after at least 9s, got rc=$rc after ${secs}s"
  cat /tmp/wait-for-mysql.log
  exit 1
fi
if ! grep -q "readiness timeout paused" /tmp/wait-for-mysql.log; then
  echo "FAIL: expected a log line about the paused readiness timeout"
  cat /tmp/wait-for-mysql.log
  exit 1
fi
echo "OK: readiness timeout paused for the whole transfer (${secs}s)"

# 3. GALERIA_SST_TIMEOUT bounds a transfer that never finishes.
start_fake_sst 120
export GALERIA_SST_TIMEOUT=5
read -r rc secs < <(run_wait 3)
stop_fake_sst
if [ "$rc" != "1" ] || [ "$secs" -lt 4 ] || [ "$secs" -gt 20 ]; then
  echo "FAIL: expected GALERIA_SST_TIMEOUT=5 to give up after ~5s, got rc=$rc after ${secs}s"
  cat /tmp/wait-for-mysql.log
  exit 1
fi
if ! grep -q "State transfer did not finish within 5s" /tmp/wait-for-mysql.log; then
  echo "FAIL: expected a log line about the exceeded SST timeout"
  cat /tmp/wait-for-mysql.log
  exit 1
fi
echo "OK: GALERIA_SST_TIMEOUT bounds a stuck transfer (${secs}s)"
INNER

if [ "$unit_rc" -ne 0 ]; then
  log "FAIL: wait_for_mysql did not behave as expected inside the image"
  exit 1
fi

# Part 2: the entrypoint honors GALERIA_READY_TIMEOUT (0 forces an immediate
# timeout, so no timing assumptions about MariaDB startup are needed).
log "Starting container with GALERIA_READY_TIMEOUT=0 (expected: fail fast with the configured value in the log)..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  -e GALERIA_READY_TIMEOUT=0 \
  "$IMAGE" >/dev/null

elapsed=0
running="true"
while [ "$elapsed" -lt 90 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$running" = "true" ]; then
  log "Expected container to exit with GALERIA_READY_TIMEOUT=0"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -60
  exit 1
fi

logs="$(docker logs "$CONTAINER_NAME" 2>&1 || true)"
if ! echo "$logs" | grep -q "MariaDB did not become ready in time (GALERIA_READY_TIMEOUT=0s"; then
  log "Expected the readiness failure to report the configured timeouts"
  echo "$logs" | tail -60
  exit 1
fi

docker rm -fv "$CONTAINER_NAME" >/dev/null 2>&1 || true

log "Case 12.sst-readiness-wait passed."

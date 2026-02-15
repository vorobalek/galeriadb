#!/usr/bin/env bash
set -euo pipefail

log "Case 09.non-candidate-exits-without-primary: non-candidate must fail fast when no primary appears"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

start_ts="$(date +%s)"
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera2 \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1,galera2,galera3 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

log "Waiting for container to exit (up to 70s)..."
elapsed=0
running="true"
while [ "$elapsed" -lt 70 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$running" = "true" ]; then
  log "Expected container to exit when no primary is available"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_NAME" 2>/dev/null || echo "0")"
if [ "$exit_code" = "0" ]; then
  log "Expected non-zero exit code when no primary is available, got $exit_code"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

duration="$(($(date +%s) - start_ts))"
if [ "$duration" -gt 90 ]; then
  log "Exit took too long (${duration}s); expected fail-fast behavior"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

logs="$(docker logs "$CONTAINER_NAME" 2>&1 || true)"
if ! echo "$logs" | grep -q "Non-candidate did not reach Synced state\|failed to reach primary view"; then
  log "Expected fail-fast reason in logs"
  echo "$logs" | tail -120
  exit 1
fi

log "Case 09.non-candidate-exits-without-primary passed in ${duration}s."

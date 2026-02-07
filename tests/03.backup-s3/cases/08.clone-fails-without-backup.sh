#!/usr/bin/env bash
log "Case 08.clone-fails-without-backup: clone must fail on empty S3 path"
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio
start_galera_clone

log "Waiting for clone attempt to fail (up to 60s)..."
elapsed=0
running="true"
while [ "$elapsed" -lt 60 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$GALERA_NAME" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$running" = "true" ]; then
  log "Clone did not fail in time; container is still running"
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
fi

exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$GALERA_NAME" 2>/dev/null || echo "0")"
if [ "$exit_code" = "0" ]; then
  log "Expected non-zero exit code when no backup exists, got: $exit_code"
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
fi

logs="$(docker logs "$GALERA_NAME" 2>&1 || true)"
if ! echo "$logs" | grep -q "No backups found under"; then
  log "Expected error about missing backups, got logs:"
  echo "$logs" | tail -80
  exit 1
fi

log "Case 08.clone-fails-without-backup passed."

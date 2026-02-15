#!/usr/bin/env bash
set -euo pipefail

log "Case 10.auto-migrate-refuses-newer-datadir: refuse startup when data version is newer than server"

VOL_NAME="galeriadb-smoke-upgrade-guard-$$"
docker volume create "$VOL_NAME" >/dev/null

cleanup_case() {
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker volume rm "$VOL_NAME" 2>/dev/null || true
}
trap cleanup_case EXIT

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

log "Bootstrapping initial datadir..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -v "$VOL_NAME:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

elapsed=0
while [ "$elapsed" -lt 60 ]; do
  if docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! docker exec "$CONTAINER_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
  log "Initial container did not become ready"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

log "Injecting newer upgrade marker into datadir..."
docker run --rm \
  -v "$VOL_NAME:/var/lib/mysql" \
  --entrypoint sh \
  "$IMAGE" \
  -c "printf '%s\n' '99.0.0-MariaDB' > /var/lib/mysql/mysql_upgrade_info"

log "Starting container again; it must refuse startup..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname galera1 \
  -v "$VOL_NAME:/var/lib/mysql" \
  -e GALERIA_ROOT_PASSWORD="$PASS" \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_CLUSTER_NAME=galera_cluster \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
  "$IMAGE"

elapsed=0
running="true"
while [ "$elapsed" -lt 120 ]; do
  running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

if [ "$running" = "true" ]; then
  log "Expected startup refusal, but container is still running"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_NAME" 2>/dev/null || echo "0")"
if [ "$exit_code" = "0" ]; then
  log "Expected non-zero exit code when data version is newer, got $exit_code"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -120
  exit 1
fi

logs="$(docker logs "$CONTAINER_NAME" 2>&1 || true)"
if ! echo "$logs" | grep -q "data version .* newer than server .* refusing to start"; then
  log "Expected refusal message in logs"
  echo "$logs" | tail -120
  exit 1
fi

log "Case 10.auto-migrate-refuses-newer-datadir passed."

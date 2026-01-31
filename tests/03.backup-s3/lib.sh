#!/usr/bin/env bash
NET_NAME="galeriadb-backup-test-$$"
MINIO_NAME="minio-backup-$$"
GALERA_NAME="galera-backup-$$"
PASS="${GALERIA_ROOT_PASSWORD:-secret}"
S3_BUCKET="backup"
S3_PREFIX="mariadb"
MINIO_ACCESS="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET="${MINIO_SECRET_KEY:-minioadmin}"

EXTRA_CONTAINERS=()
EXTRA_VOLUMES=()

register_container() { EXTRA_CONTAINERS+=("$1"); }
register_volume() { EXTRA_VOLUMES+=("$1"); }

cleanup_backup_s3() {
  log "Cleaning up containers and network"
  for c in "${EXTRA_CONTAINERS[@]}"; do
    docker rm -f "$c" 2>/dev/null || true
  done
  for v in "${EXTRA_VOLUMES[@]}"; do
    docker volume rm "$v" 2>/dev/null || true
  done
  docker rm -f "$GALERA_NAME" 2>/dev/null || true
  docker rm -f "$MINIO_NAME" 2>/dev/null || true
  docker network rm "$NET_NAME" 2>/dev/null || true
}

start_minio() {
  log "Starting MinIO..."
  docker network create "$NET_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$MINIO_NAME" \
    --network "$NET_NAME" \
    -e MINIO_ROOT_USER="$MINIO_ACCESS" \
    -e MINIO_ROOT_PASSWORD="$MINIO_SECRET" \
    minio/minio:latest server /data
  wait_minio_ready
}

wait_minio_ready() {
  local elapsed=0
  log "Waiting for MinIO (up to 30s)..."
  while [ "$elapsed" -lt 30 ]; do
    if docker run --rm --network "$NET_NAME" curlimages/curl:latest -sf --max-time 2 "http://${MINIO_NAME}:9000/minio/health/live" >/dev/null 2>&1; then
      log "MinIO ready"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "MinIO did not become ready"
  return 1
}

start_galera() {
  log "Starting Galera node (single, bootstrap)..."
  local extra=()
  if [ -n "${GALERIA_BACKUP_SCHEDULE:-}" ]; then
    extra+=(-e "GALERIA_BACKUP_SCHEDULE=${GALERIA_BACKUP_SCHEDULE}")
  fi
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    -e GALERIA_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
    -e AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
    -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
    -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "${extra[@]}" \
    "$IMAGE"
}

start_galera_clone() {
  log "Starting Galera node (single, bootstrap) with clone..."
  local extra=()
  if [ -n "${GALERIA_CLONE_FROM:-}" ]; then
    extra+=(-e "GALERIA_CLONE_FROM=${GALERIA_CLONE_FROM}")
  fi
  docker run -d \
    --name "$GALERA_NAME" \
    --hostname galera1 \
    --network "$NET_NAME" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    -e GALERIA_CLONE_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
    -e CLONE_AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
    -e CLONE_AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
    -e CLONE_AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
    -e CLONE_AWS_DEFAULT_REGION=us-east-1 \
    "${extra[@]}" \
    "$IMAGE"
}

wait_mysql_ready() {
  log "Waiting for MySQL readiness (up to 120s)..."
  local elapsed=0
  while [ "$elapsed" -lt 120 ]; do
    if docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "MySQL did not become ready"
  return 1
}

wait_synced() {
  log "Waiting for Synced (up to 60s)..."
  local elapsed=0 state
  while [ "$elapsed" -lt 60 ]; do
    state=$(docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$state" = "Synced" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "Node did not reach Synced (got $state)"
  return 1
}

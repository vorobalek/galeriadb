#!/usr/bin/env bash
# Case: create cluster -> backup -> stop -> wipe volumes -> restore -> verify cluster and data.
# Sourced from entrypoint. Uses 00.common.sh helpers.

log "Case 06.cluster-restore: cluster backup -> wipe -> restore -> verify"
# Clean up any containers from previous cases
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio

CLUSTER_ID="cluster-$$"
G1="galera1-${CLUSTER_ID}"
G2="galera2-${CLUSTER_ID}"
G3="galera3-${CLUSTER_ID}"
VOL1="galera1-data-${CLUSTER_ID}"
VOL2="galera2-data-${CLUSTER_ID}"
VOL3="galera3-data-${CLUSTER_ID}"

register_container "$G1"
register_container "$G2"
register_container "$G3"
register_volume "$VOL1"
register_volume "$VOL2"
register_volume "$VOL3"

docker volume create "$VOL1" >/dev/null
docker volume create "$VOL2" >/dev/null
docker volume create "$VOL3" >/dev/null

start_node() {
  local name="$1"
  local host="$2"
  local volume="$3"
  shift 3
  docker run -d \
    --name "$name" \
    --hostname "$host" \
    --network "$NET_NAME" \
    --network-alias "$host" \
    -v "$volume:/var/lib/mysql" \
    -e GALERIA_ROOT_PASSWORD="$PASS" \
    -e GALERIA_PEERS=galera1,galera2,galera3 \
    -e GALERIA_CLUSTER_NAME=galera_cluster \
    -e GALERIA_BOOTSTRAP_CANDIDATE=galera1 \
    "$@" \
    "$IMAGE"
}

wait_mysql_ready_named() {
  local name="$1"
  local timeout="${2:-120}"
  local elapsed=0
  log "Waiting for $name MySQL (up to ${timeout}s)..."
  while [ "$elapsed" -lt "$timeout" ]; do
    if docker exec "$name" mariadb -u root -p"$PASS" -e "SELECT 1" &>/dev/null; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "$name MySQL did not become ready"
  return 1
}

wait_synced_named() {
  local name="$1"
  local timeout="${2:-60}"
  local elapsed=0 state
  log "Waiting for $name Synced (up to ${timeout}s)..."
  while [ "$elapsed" -lt "$timeout" ]; do
    state=$(docker exec "$name" mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$state" = "Synced" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "$name did not reach Synced (got $state)"
  return 1
}

wait_cluster_size() {
  local name="$1"
  local expected="$2"
  local timeout="${3:-180}"
  local elapsed=0 size
  log "Waiting for cluster size=${expected} (up to ${timeout}s)..."
  while [ "$elapsed" -lt "$timeout" ]; do
    size=$(docker exec "$name" mariadb -u root -p"$PASS" -Nse "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}' || echo "0")
    if [ "${size:-0}" = "$expected" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "Cluster size did not reach ${expected} (got ${size:-0})"
  return 1
}

log "Starting initial cluster..."
start_node "$G1" galera1 "$VOL1" \
  -e GALERIA_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
  -e AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
  -e AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
  -e AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
  -e AWS_DEFAULT_REGION=us-east-1

wait_mysql_ready_named "$G1" 120 || {
  docker logs "$G1" 2>&1 | tail -80
  exit 1
}
wait_synced_named "$G1" 60 || {
  docker logs "$G1" 2>&1 | tail -60
  exit 1
}

start_node "$G2" galera2 "$VOL2"
start_node "$G3" galera3 "$VOL3"

wait_cluster_size "$G1" 3 180 || {
  docker logs "$G1" 2>&1 | tail -80
  exit 1
}

log "Creating test data..."
docker exec "$G1" mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_cluster; CREATE TABLE ci_cluster (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_cluster VALUES (1, 'cluster-restore');"

log "Creating S3 bucket..."
docker exec "$G1" aws s3 mb "s3://${S3_BUCKET}" 2>/dev/null || true

log "Running galera-backup.sh..."
docker exec -e MYSQL_PWD="$PASS" "$G1" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh failed"
  docker logs "$G1" 2>&1 | tail -30
  exit 1
}

latest=$(docker exec "$G1" aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/galera1/" 2>/dev/null | awk '{print $4}' | sort | tail -1)
if [ -z "${latest:-}" ]; then
  log "No backup found for galera1"
  exit 1
fi
CLONE_FROM="galera1/${latest}"

log "Stopping cluster and wiping volumes..."
docker rm -f "$G1" "$G2" "$G3" 2>/dev/null || true
docker volume rm "$VOL1" "$VOL2" "$VOL3" 2>/dev/null || true
docker volume create "$VOL1" >/dev/null
docker volume create "$VOL2" >/dev/null
docker volume create "$VOL3" >/dev/null

log "Starting cluster from backup..."
start_node "$G1" galera1 "$VOL1" \
  -e GALERIA_CLONE_BACKUP_S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}" \
  -e GALERIA_CLONE_FROM="$CLONE_FROM" \
  -e CLONE_AWS_ENDPOINT_URL="http://${MINIO_NAME}:9000" \
  -e CLONE_AWS_ACCESS_KEY_ID="$MINIO_ACCESS" \
  -e CLONE_AWS_SECRET_ACCESS_KEY="$MINIO_SECRET" \
  -e CLONE_AWS_DEFAULT_REGION=us-east-1

wait_mysql_ready_named "$G1" 180 || {
  docker logs "$G1" 2>&1 | tail -80
  exit 1
}
wait_synced_named "$G1" 60 || {
  docker logs "$G1" 2>&1 | tail -60
  exit 1
}

start_node "$G2" galera2 "$VOL2"
start_node "$G3" galera3 "$VOL3"

wait_cluster_size "$G1" 3 180 || {
  docker logs "$G1" 2>&1 | tail -80
  exit 1
}

val=$(docker exec "$G2" mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_cluster WHERE id=1" 2>/dev/null || echo "")
if [ "$val" != "cluster-restore" ]; then
  log "Restore failed: expected 'cluster-restore', got '$val'"
  docker logs "$G1" 2>&1 | tail -80
  exit 1
fi
log "Case 06.cluster-restore passed."

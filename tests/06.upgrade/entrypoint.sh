#!/usr/bin/env bash
# Upgrade test: cluster 11.8 (from Docker Hub) → 12.1 (local build).
# Uses galeriadb/11.8:latest from Docker Hub and galeriadb/12.1:local from 'make build'.
# Usage: ./tests/06.upgrade/entrypoint.sh
# Uses same 3-node + HAProxy compose as 02.deploy; runs with 11.8, then restarts with 12.1 (same volumes).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/../02.deploy"
CASES_DIR="${DEPLOY_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE_11_8="${IMAGE_11_8:-galeriadb/11.8:latest}"
IMAGE_12_1="${IMAGE_12_1:-galeriadb/12.1:local}"

for img in "$IMAGE_11_8" "$IMAGE_12_1"; do
  docker image inspect "$img" >/dev/null 2>&1 || {
    log "Image $img not found. Pull from Docker Hub: docker pull galeriadb/11.8:latest ; run 'make build' for 12.1."
    exit 1
  }
done

COMPOSE_FILE="${DEPLOY_DIR}/compose/compose.test.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-galeriadb-upgrade-test}"
export HOST_WORKSPACE="${HOST_WORKSPACE:-$PWD}"
export PASS="secret"

# shellcheck source=../02.deploy/cases/00.common.sh disable=SC1091
source "${CASES_DIR}/00.common.sh"

cleanup() {
  local rv=$?
  if [ $rv -ne 0 ]; then
    logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  fi
  log "Shutting down compose project $PROJECT_NAME"
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
  exit $rv
}
trap cleanup EXIT

# --- Phase 1: start cluster with 11.8 ---
log "Phase 1: start cluster with $IMAGE_11_8"
export COMPOSE_IMAGE="$IMAGE_11_8"
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

# Verify 11.8
version_11=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
  mariadb -u root -p"$PASS" -Nse "SELECT VERSION()" 2>/dev/null || echo "")
log "Phase 1 version: $version_11"
if [[ "$version_11" != *"11.8"* ]]; then
  log "Expected 11.8 in version string, got: $version_11"
  exit 1
fi

# --- Stop 11.8, keep volumes ---
log "Stopping 11.8 cluster (keeping volumes)..."
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down --remove-orphans

# --- Phase 2: start cluster with 12.1 (mariadb-upgrade runs in entrypoint) ---
log "Phase 2: start cluster with $IMAGE_12_1"
export COMPOSE_IMAGE="$IMAGE_12_1"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d

wait_cluster_3 || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}
wait_synced || {
  logdump "$COMPOSE_FILE" "$PROJECT_NAME"
  exit 1
}

# Verify 12.1
version_12=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 \
  mariadb -u root -p"$PASS" -Nse "SELECT VERSION()" 2>/dev/null || echo "")
log "Phase 2 version: $version_12"
if [[ "$version_12" != *"12.1"* ]]; then
  log "Expected 12.1 in version string, got: $version_12"
  exit 1
fi

# Verify data survived upgrade (poll: replication may lag briefly after Synced)
log "Verifying data on all nodes (poll up to 30s)..."
v1="" v2="" v3=""
for attempt in $(seq 1 30); do
  v1=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera1 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  v2=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera2 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  v3=$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec -T galera3 mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_test WHERE id=1" 2>/dev/null || echo "")
  if [ "$v1" = "from_node1" ] && [ "$v2" = "from_node1" ] && [ "$v3" = "from_node1" ]; then
    break
  fi
  [ "$attempt" -lt 30 ] && sleep 1
done
if [ "$v1" != "from_node1" ] || [ "$v2" != "from_node1" ] || [ "$v3" != "from_node1" ]; then
  log "Data check failed after upgrade: galera1='$v1' galera2='$v2' galera3='$v3'"
  exit 1
fi
log "Upgrade test passed: 11.8 → 12.1, data preserved."

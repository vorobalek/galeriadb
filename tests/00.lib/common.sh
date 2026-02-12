#!/usr/bin/env bash
# Test helpers.

set -euo pipefail

ARTIFACTS_DIR="${ARTIFACTS_DIR:-./artifacts}"

log() { echo "[$(date -Is)] $*"; }

require_image() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1 || {
    log "Image $image not found. Run 'make build' first."
    exit 1
  }
}

poll_until() {
  local label="$1" timeout="$2"
  shift 2
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "poll_until: ${label} did not succeed within ${timeout}s"
  return 1
}

wait_http_ok() {
  local url="$1"
  local timeout="${2:-30}"
  poll_until "HTTP $url" "$timeout" curl -sf --max-time 5 "$url"
}

wait_mysql() {
  local host="$1"
  local port="${2:-3306}"
  local user="$3"
  local pass="$4"
  local timeout="${5:-60}"
  poll_until "MySQL $host:$port" "$timeout" mariadb -h "$host" -P "$port" -u "$user" -p"$pass" -e "SELECT 1"
}

retry() {
  local max="$1"
  local delay="$2"
  shift 2
  local attempt=1
  while [ "$attempt" -le "$max" ]; do
    if "$@"; then
      return 0
    fi
    log "retry $attempt/$max failed, waiting ${delay}s"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  return 1
}

logdump() {
  local compose_file="${1:-}"
  local project="${2:-galeriadb-test}"
  mkdir -p "$ARTIFACTS_DIR"
  log "Collecting diagnostics into $ARTIFACTS_DIR"
  docker ps -a >"$ARTIFACTS_DIR/docker-ps.txt" 2>&1 || true
  docker network ls >"$ARTIFACTS_DIR/docker-network-ls.txt" 2>&1 || true
  docker volume ls >"$ARTIFACTS_DIR/docker-volume-ls.txt" 2>&1 || true
  if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
    docker compose -f "$compose_file" -p "$project" logs --no-color >"$ARTIFACTS_DIR/compose-logs.txt" 2>&1 || true
    for cid in $(docker compose -f "$compose_file" -p "$project" ps -aq 2>/dev/null || true); do
      [ -z "$cid" ] && continue
      name=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's/^\///')
      docker inspect "$cid" >"$ARTIFACTS_DIR/inspect-${name}.json" 2>&1 || true
    done
  fi
}

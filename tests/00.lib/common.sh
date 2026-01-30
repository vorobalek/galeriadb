#!/usr/bin/env bash
# Common helpers for test scripts: wait_for, retry, logdump.
# Source from tests/0*.entrypoint.sh via: source "${SCRIPT_DIR}/../00.lib/common.sh"

set -euo pipefail

ARTIFACTS_DIR="${ARTIFACTS_DIR:-./artifacts}"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }

# Wait until HTTP endpoint returns 200. Usage: wait_http_ok URL timeout_sec
wait_http_ok() {
  local url="$1"
  local timeout="${2:-30}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "wait_http_ok: $url did not return 200 within ${timeout}s"
  return 1
}

# Wait until MySQL accepts connections. Usage: wait_mysql host port user pass timeout_sec
wait_mysql() {
  local host="$1"
  local port="${2:-3306}"
  local user="$3"
  local pass="$4"
  local timeout="${5:-60}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if mariadb -h "$host" -P "$port" -u "$user" -p"$pass" -e "SELECT 1" &>/dev/null; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  log "wait_mysql: $host:$port did not become ready within ${timeout}s"
  return 1
}

# Retry command N times with delay. Usage: retry N delay_sec command...
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

# Collect diagnostic logs on failure into ARTIFACTS_DIR.
# Usage: logdump compose_file [compose_project]
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

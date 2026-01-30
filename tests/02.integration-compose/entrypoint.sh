#!/usr/bin/env bash
# Integration test: 3 Galera nodes + HAProxy. Runs cases from cases/ (01.all, 02.mixed, 03.restart).
# Usage: ./tests/02.integration-compose/entrypoint.sh [IMAGE] [CASE]
#   CASE: 01.all | 02.mixed | 03.restart (default: run all in order)
# Env: COMPOSE_IMAGE, INTEGRATION_SCENARIO (legacy: all|mixed|restart → 01.all|02.mixed|03.restart), ARTIFACTS_DIR
# IMAGE defaults to galeriadb/11.8:local (use 'make build' first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE="${1:-${COMPOSE_IMAGE:-galeriadb/11.8:local}}"
CASE_ARG="${2:-${INTEGRATION_SCENARIO:-}}"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { log "Image $IMAGE not found. Run 'make build' first."; exit 1; }

COMPOSE_FILE="${SCRIPT_DIR}/compose/compose.test.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-galeriadb-test}"
PASS="secret"
export COMPOSE_IMAGE="$IMAGE"

# Map legacy scenario names to case scripts
case "$CASE_ARG" in
  all)   CASE_ARG="01.all" ;;
  mixed) CASE_ARG="02.mixed" ;;
  restart) CASE_ARG="03.restart" ;;
esac

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

# shellcheck source=cases/00.common.sh
source "${CASES_DIR}/00.common.sh"

if [ -n "$CASE_ARG" ]; then
  case "$CASE_ARG" in
    01.all|02.mixed|03.restart)
      # shellcheck source=cases/01.all.sh
      source "${CASES_DIR}/${CASE_ARG}.sh"
      ;;
    *)
      log "Unknown case: $CASE_ARG (use 01.all, 02.mixed, 03.restart)"
      exit 1
      ;;
  esac
else
  source "${CASES_DIR}/01.all.sh"
  source "${CASES_DIR}/02.mixed.sh"
  source "${CASES_DIR}/03.restart.sh"
fi

log "Integration test passed."

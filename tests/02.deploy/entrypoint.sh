#!/usr/bin/env bash
# Deploy test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE="${1:-${COMPOSE_IMAGE:-galeriadb/12.1:local}}"
CASE_ARG="${2:-${CASE:-}}"
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  log "Image $IMAGE not found. Run 'make build' first."
  exit 1
}

COMPOSE_FILE="${SCRIPT_DIR}/compose/compose.test.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-galeriadb-test}"
export HOST_WORKSPACE="${HOST_WORKSPACE:-$PWD}"
export PASS="secret"
export COMPOSE_IMAGE="$IMAGE"

case "$CASE_ARG" in
  all) CASE_ARG="01.all" ;;
  mixed) CASE_ARG="02.mixed" ;;
  restart) CASE_ARG="03.restart" ;;
  full-restart) CASE_ARG="04.full-restart" ;;
  consensus) CASE_ARG="05.consensus" ;;
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

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

if [ -n "$CASE_ARG" ]; then
  case "$CASE_ARG" in
    01.all | 02.mixed | 03.restart | 04.full-restart | 05.consensus)
      # shellcheck disable=SC1090,SC1091
      source "${CASES_DIR}/${CASE_ARG}.sh"
      ;;
    *)
      log "Unknown case: $CASE_ARG (use 01.all, 02.mixed, 03.restart, 04.full-restart, 05.consensus)"
      exit 1
      ;;
  esac
else
  # shellcheck disable=SC1091
  source "${CASES_DIR}/01.all.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/02.mixed.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/03.restart.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/04.full-restart.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/05.consensus.sh"
fi

log "Deploy test passed."

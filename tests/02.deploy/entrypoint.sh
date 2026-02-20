#!/usr/bin/env bash
# Deploy test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"
# shellcheck source=../00.lib/test-runner.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/test-runner.sh"

IMAGE="${1:-${COMPOSE_IMAGE:-galeriadb/12.1:local}}"
CASE_ARG="${2:-${CASE:-}}"
require_image "$IMAGE"

COMPOSE_FILE="${SCRIPT_DIR}/compose/compose.test.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-galeriadb-test}"
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

log "Deploy test: image=$IMAGE"
run_suite "$CASES_DIR" "$CASE_ARG"
log "Deploy test passed."

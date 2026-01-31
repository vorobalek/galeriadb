#!/usr/bin/env bash
# Smoke test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE="${1:-galeriadb/12.1:local}"
CASE_ARG="${2:-}"
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  log "Image $IMAGE not found. Run 'make build' first."
  exit 1
}

CONTAINER_NAME="galeriadb-smoke-$$"
export IMAGE
export CONTAINER_NAME

cleanup() {
  log "Cleaning up container $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

run_case() {
  local name="$1"
  # shellcheck disable=SC1090
  source "${CASES_DIR}/${name}.sh"
}

if [ -n "$CASE_ARG" ]; then
  case "$CASE_ARG" in
    01.all-required | 02.missing-peers | 03.missing-root-password | 04.missing-bootstrap-candidate | 05.healthcheck-user)
      run_case "$CASE_ARG"
      ;;
    *)
      log "Unknown case: $CASE_ARG. Use 01.all-required | 02.missing-peers | 03.missing-root-password | 04.missing-bootstrap-candidate | 05.healthcheck-user"
      exit 1
      ;;
  esac
else
  log "Smoke test: image=$IMAGE (all cases)"
  run_case "01.all-required"
  run_case "02.missing-peers"
  run_case "03.missing-root-password"
  run_case "04.missing-bootstrap-candidate"
  run_case "05.healthcheck-user"
  log "Smoke test passed (all cases)."
fi

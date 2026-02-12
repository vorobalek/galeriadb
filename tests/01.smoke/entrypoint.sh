#!/usr/bin/env bash
# Smoke test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"
# shellcheck source=../00.lib/test-runner.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/test-runner.sh"

IMAGE="${1:-galeriadb/12.1:local}"
CASE_ARG="${2:-}"
require_image "$IMAGE"

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

log "Smoke test: image=$IMAGE"
run_suite "$CASES_DIR" "$CASE_ARG"
log "Smoke test passed."

#!/usr/bin/env bash
# S3 backup test runner.

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

log "S3 backup test: image=$IMAGE"

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
cleanup() { cleanup_backup_s3; }
trap cleanup EXIT

run_suite "$CASES_DIR" "$CASE_ARG"
log "S3 backup test passed."

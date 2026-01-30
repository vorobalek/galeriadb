#!/usr/bin/env bash
# S3 backup test: MinIO + Galera, backup to S3. Runs cases from cases/ (01.backup-to-s3, 02.fail-without-s3-config, 03.retention-deletes-old).
# Usage: ./tests/03.backup-s3/entrypoint.sh [IMAGE] [CASE]
#   CASE: 01.backup-to-s3 | 02.fail-without-s3-config | 03.retention-deletes-old (default: run all in order)
# IMAGE defaults to galeriadb/12.1:local (use 'make build' first)

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

log "S3 backup test: image=$IMAGE"

# shellcheck source=cases/00.common.sh disable=SC1091
source "${CASES_DIR}/00.common.sh"
cleanup() { cleanup_backup_s3; }
trap cleanup EXIT

if [ -n "$CASE_ARG" ]; then
  case "$CASE_ARG" in
    01.backup-to-s3)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/01.backup-to-s3.sh"
      ;;
    02.fail-without-s3-config)
      # 02 needs galera running; start minimal stack first
      start_minio
      start_galera
      wait_mysql_ready || {
        docker logs "$GALERA_NAME" 2>&1 | tail -80
        exit 1
      }
      wait_synced || {
        docker logs "$GALERA_NAME" 2>&1 | tail -50
        exit 1
      }
      # shellcheck disable=SC1091
      source "${CASES_DIR}/02.fail-without-s3-config.sh"
      ;;
    03.retention-deletes-old)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/03.retention-deletes-old.sh"
      ;;
    *)
      log "Unknown case: $CASE_ARG (use 01.backup-to-s3, 02.fail-without-s3-config, 03.retention-deletes-old)"
      exit 1
      ;;
  esac
else
  # shellcheck disable=SC1091
  source "${CASES_DIR}/01.backup-to-s3.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/02.fail-without-s3-config.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/03.retention-deletes-old.sh"
fi

log "S3 backup test passed."

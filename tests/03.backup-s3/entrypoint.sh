#!/usr/bin/env bash
# S3 backup test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${SCRIPT_DIR}/cases"
# shellcheck source=../00.lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/../00.lib/common.sh"

IMAGE="${1:-galeriadb/11.8:local}"
CASE_ARG="${2:-}"
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  log "Image $IMAGE not found. Run 'make build' first."
  exit 1
}

log "S3 backup test: image=$IMAGE"

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
cleanup() { cleanup_backup_s3; }
trap cleanup EXIT

if [ -n "$CASE_ARG" ]; then
  case "$CASE_ARG" in
    01.backup-to-s3)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/01.backup-to-s3.sh"
      ;;
    02.fail-without-s3-config)
      # Case 02 expects a running stack.
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
    04.cron-backup)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/04.cron-backup.sh"
      ;;
    05.clone-on-empty)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/05.clone-on-empty.sh"
      ;;
    06.cluster-restore)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/06.cluster-restore.sh"
      ;;
    08.clone-fails-without-backup)
      # shellcheck disable=SC1091
      source "${CASES_DIR}/08.clone-fails-without-backup.sh"
      ;;
    *)
      log "Unknown case: $CASE_ARG (use 01.backup-to-s3, 02.fail-without-s3-config, 03.retention-deletes-old, 04.cron-backup, 05.clone-on-empty, 06.cluster-restore, 08.clone-fails-without-backup)"
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
  # shellcheck disable=SC1091
  source "${CASES_DIR}/04.cron-backup.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/05.clone-on-empty.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/06.cluster-restore.sh"
  # shellcheck disable=SC1091
  source "${CASES_DIR}/08.clone-fails-without-backup.sh"
fi

log "S3 backup test passed."

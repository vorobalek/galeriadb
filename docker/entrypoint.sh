#!/bin/bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-/usr/local/bin}"
ENTRYPOINT_DIR="${ENTRYPOINT_DIR:-/usr/local/bin/entrypoint.d}"
ORIG_ARGS=("$@")

export SCRIPT_DIR ENTRYPOINT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/entrypoint-lib.sh"

run_stage() {
  local stage="$1"
  set -- "${ORIG_ARGS[@]}"
  # shellcheck source=/dev/null
  source "${ENTRYPOINT_DIR}/${stage}"
}

run_stage "00-env.sh"
run_stage "10-discovery.sh"
run_stage "20-write-config.sh"
run_stage "30-healthcheck.sh"
run_stage "40-init-or-clone.sh"
run_stage "50-safe-to-bootstrap.sh"
run_stage "60-start-mariadb.sh"
run_stage "70-wait-ready.sh"
run_stage "80-ensure-root.sh"
run_stage "85-auto-migrate.sh"
run_stage "90-backup-cron.sh"

: "${MYSQLD_PID:?}"
wait "$MYSQLD_PID"

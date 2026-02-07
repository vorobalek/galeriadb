#!/bin/bash
set -euo pipefail

SCRIPT_DIR="/usr/local/bin"
ENTRYPOINT_DIR="/usr/local/bin/entrypoint.d"
ORIG_ARGS=("$@")

export SCRIPT_DIR ENTRYPOINT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/entrypoint-lib.sh"

run_stage "00-env.sh" "${ORIG_ARGS[@]}"
run_stage "10-discovery.sh" "${ORIG_ARGS[@]}"
run_stage "20-write-config.sh" "${ORIG_ARGS[@]}"
run_stage "30-healthcheck.sh" "${ORIG_ARGS[@]}"
run_stage "40-init-or-clone.sh" "${ORIG_ARGS[@]}"
run_stage "50-safe-to-bootstrap.sh" "${ORIG_ARGS[@]}"
run_stage "60-start-mariadb.sh" "${ORIG_ARGS[@]}"
run_stage "70-wait-ready.sh" "${ORIG_ARGS[@]}"
run_stage "80-ensure-root.sh" "${ORIG_ARGS[@]}"
run_stage "85-auto-migrate.sh" "${ORIG_ARGS[@]}"
run_stage "90-backup-cron.sh" "${ORIG_ARGS[@]}"

: "${MYSQLD_PID:?}"

trap shutdown SIGTERM SIGINT

wait "$MYSQLD_PID"

#!/usr/bin/env bash
# Common for smoke cases. Expects: IMAGE (set by entrypoint).
# Optional env: GALERIA_ROOT_PASSWORD (used in 01.all-required; default secret for tests).

PASS="${GALERIA_ROOT_PASSWORD:-secret}"

# Run image with given env; expect exit code 1 and stderr containing "Required environment variable VAR_NAME is not set".
# Usage: expect_required_var_fail var_name [extra_docker_run_args...]
# Example: expect_required_var_fail GALERIA_PEERS -e GALERIA_ROOT_PASSWORD=secret -e GALERIA_BOOTSTRAP_CANDIDATE=galera1
# Pass env with -e; omit the variable under test.
expect_required_var_fail() {
  local var_name="$1"
  shift
  local err code
  set +e
  err=$(docker run --rm "$@" "$IMAGE" 2>&1)
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    log "FAIL: expected non-zero exit when $var_name is missing, got 0"
    return 1
  fi
  if ! echo "$err" | grep -q "Required environment variable $var_name is not set"; then
    log "FAIL: expected stderr to contain 'Required environment variable $var_name is not set', got: $err"
    return 1
  fi
  log "OK: container exits with error when $var_name is missing"
  return 0
}

#!/usr/bin/env bash
# Smoke test helpers.

export PASS="${GALERIA_ROOT_PASSWORD:-secret}"

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

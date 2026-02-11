#!/usr/bin/env bash
# Shared helpers for galera-* scripts.

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

# --- S3 helpers (backup, clone) ---

# resolve_s3_base URI_VAR BUCKET_VAR PATH_VAR DEFAULT_PATH ERROR_MSG
# Sets S3_BASE from either a full URI or bucket+path combination.
resolve_s3_base() {
  local uri_var="$1" bucket_var="$2" path_var="$3" default_path="$4" err_msg="$5"
  if [ -n "${!uri_var:-}" ]; then
    # shellcheck disable=SC2034 # S3_BASE is used by the caller
    S3_BASE="${!uri_var}"
  elif [ -n "${!bucket_var:-}" ]; then
    # shellcheck disable=SC2034
    S3_BASE="s3://${!bucket_var}/${!path_var:-$default_path}"
  else
    log "ERROR: $err_msg"
    return 1
  fi
}

# build_aws_opts ENDPOINT_URL_VAR
# Populates the AWS_OPTS array with --endpoint-url if the variable is set.
build_aws_opts() {
  local endpoint_var="$1"
  AWS_OPTS=()
  [ -n "${!endpoint_var:-}" ] && AWS_OPTS+=(--endpoint-url "${!endpoint_var}")
}

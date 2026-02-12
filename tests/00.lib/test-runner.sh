#!/usr/bin/env bash
# Shared test suite runner with auto-discovery of cases.

run_suite() {
  local cases_dir="$1"
  local case_arg="${2:-}"
  if [ -n "$case_arg" ]; then
    local case_file="${cases_dir}/${case_arg}.sh"
    if [ ! -f "$case_file" ]; then
      local available
      available=$(find "$cases_dir" -maxdepth 1 -name '*.sh' -printf '%f\n' 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ', ' | sed 's/,$//')
      log "Unknown case: $case_arg (available: $available)"
      exit 1
    fi
    # shellcheck disable=SC1090
    source "$case_file"
  else
    local f
    for f in "$cases_dir"/*.sh; do
      [ -f "$f" ] || continue
      # shellcheck disable=SC1090
      source "$f"
    done
  fi
}

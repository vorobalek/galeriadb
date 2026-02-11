#!/usr/bin/env bash
# Shared helpers for galera-http-* scripts.

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

consume_http_request() {
  while IFS= read -r -t 0.2 line 2>/dev/null; do
    line="${line%$'\r'}"
    [ -z "$line" ] && break
  done
}

http_response() {
  local code="$1"
  local body="${2:-}"
  printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
    "$code" "${#body}" "$body"
}

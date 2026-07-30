#!/usr/bin/env bash
# Shared helpers for galera-http-* scripts.

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

# Reads the request line and headers from stdin. The requested path is left in
# REQUEST_PATH (defaults to "/" when the request is empty or unreadable).
# shellcheck disable=SC2034 # REQUEST_PATH is consumed by the calling script
consume_http_request() {
  REQUEST_PATH="/"
  local line target first=1
  while IFS= read -r -t 0.2 line 2>/dev/null; do
    line="${line%$'\r'}"
    if [ "$first" = 1 ] && [ -n "$line" ]; then
      first=0
      # "GET /liveness?x=1 HTTP/1.1" -> "/liveness"
      target="${line#* }"
      target="${target%% *}"
      target="${target%%\?*}"
      [ -n "$target" ] && REQUEST_PATH="$target"
    fi
    [ -z "$line" ] && break
  done
}

http_response() {
  local code="$1"
  local body="${2:-}"
  printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
    "$code" "${#body}" "$body"
}

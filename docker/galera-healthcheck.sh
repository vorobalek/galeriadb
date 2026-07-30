#!/bin/bash
# HTTP health check on port 9200:
#   GET /          readiness for load balancers: 200 when Synced + wsrep_ready=ON.
#   GET /liveness  liveness for orchestrators: 200 while the node is Synced or
#                  legitimately taking part in a state transfer (receiving it as
#                  a joiner, serving it as a donor, applying the backlog after).
# Restarting a node that is merely "not ready" aborts its state transfer, so
# container health checks must use /liveness and load balancers must use /.

set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

MYSQL_USER="${GALERIA_HEALTHCHECK_USER:-root}"
MYSQL_PWD="${GALERIA_HEALTHCHECK_PASSWORD:-$GALERIA_ROOT_PASSWORD}"

response() {
  local code="$1"
  local body="${2:-}"
  printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
    "$code" "${#body}" "$body"
}

# Read the request line and headers; the requested path picks the check.
REQUEST_PATH="/"
first=1
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

liveness=0
case "$REQUEST_PATH" in
  /liveness | /liveness/) liveness=1 ;;
esac

# A joiner has no server to answer for it while its state transfer runs.
if [ "$liveness" = 1 ] && sst_in_progress; then
  response "200 OK" "state transfer in progress"
  exit 0
fi

result="$(
  mariadb \
    --protocol=tcp \
    --connect-timeout=1 \
    -h 127.0.0.1 \
    -u "$MYSQL_USER" -p"$MYSQL_PWD" \
    --batch --skip-column-names \
    -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('wsrep_ready','wsrep_local_state_comment');" \
    2>/dev/null || true
)"

wsrep_ready="$(awk '$1=="wsrep_ready"{print $2}' <<<"$result" | head -n1)"
wsrep_state="$(awk '$1=="wsrep_local_state_comment"{print $2}' <<<"$result" | head -n1)"

if [ "$liveness" = 1 ]; then
  case "$wsrep_state" in
    Synced | Joined | Joining* | Donor*)
      response "200 OK" "alive (${wsrep_state})"
      ;;
    *)
      response "503 Service Unavailable" "not alive (${wsrep_state:-unknown})"
      ;;
  esac
  exit 0
fi

if [ "$wsrep_ready" = "ON" ] && [ "$wsrep_state" = "Synced" ]; then
  response "200 OK" "ready"
else
  response "503 Service Unavailable" "not ready"
fi

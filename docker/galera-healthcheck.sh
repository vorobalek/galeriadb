#!/bin/bash
# HTTP health check for HAProxy: returns 200 if node is synced and ready for writes.
# Checks wsrep_ready=ON and wsrep_local_state_comment=Synced.

set -euo pipefail

MYSQL_USER="${MYSQL_CHECK_USER:-root}"
MYSQL_PWD="${MYSQL_PWD:-$GALERIA_ROOT_PASSWORD}"

response() {
  local code="$1"
  local body="${2:-}"
  printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
    "$code" "${#body}" "$body"
}

while IFS= read -r -t 0.2 line 2>/dev/null; do
  line="${line%$'\r'}"
  [ -z "$line" ] && break
done

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

if [ "$wsrep_ready" = "ON" ] && [ "$wsrep_state" = "Synced" ]; then
  response "200 OK" "ready"
else
  response "503 Service Unavailable" "not ready"
fi

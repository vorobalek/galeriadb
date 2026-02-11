#!/usr/bin/env bash
# HTTP health check: 200 when Synced + wsrep_ready=ON, 503 otherwise.

set -euo pipefail

# shellcheck source=galera-http-lib.sh
source "$(dirname "$0")/galera-http-lib.sh"

MYSQL_USER="${GALERIA_HEALTHCHECK_USER:-root}"
MYSQL_PWD="${GALERIA_HEALTHCHECK_PASSWORD:-$GALERIA_ROOT_PASSWORD}"

consume_http_request

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
  http_response "200 OK" "ready"
else
  http_response "503 Service Unavailable" "not ready"
fi

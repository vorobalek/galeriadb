#!/bin/bash
# HTTP health check for HAProxy: returns 200 if node is synced and ready for writes (master).
# Checks wsrep_ready=ON and wsrep_local_state_comment=Synced.

PORT="${GALERA_CHECK_PORT:-9200}"
MYSQL_USER="${MYSQL_CHECK_USER:-root}"
MYSQL_PWD="${MYSQL_PWD:-${GALERIA_ROOT_PASSWORD:-}}"

response() {
    local code="$1"
    local body="${2:-}"
    printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
        "$code" "${#body}" "$body"
}

# Drain request (with timeout so we don't block if client is slow)
while read -r -t 1 line 2>/dev/null; do
    [ -z "$line" ] && break
done

# Connect via overlay IP (from entrypoint's IP_ADDRESS) so server sees non-localhost and matches root@'%'
MYSQL_HOST="${IP_ADDRESS:-127.0.0.1}"
result=$(mariadb -u "$MYSQL_USER" -p"$MYSQL_PWD" -h "$MYSQL_HOST" -e "SHOW STATUS LIKE 'wsrep_ready'; SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null)
ready=$(echo "$result" | grep -E "wsrep_ready\s+ON" || true)
synced=$(echo "$result" | grep -E "wsrep_local_state_comment\s+Synced" || true)

if [ -n "$ready" ] && [ -n "$synced" ]; then
    response "200 OK" "ready"
else
    response "503 Service Unavailable" "not ready"
fi

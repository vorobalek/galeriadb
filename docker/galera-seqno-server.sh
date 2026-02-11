#!/bin/bash
set -euo pipefail

# HTTP endpoint that returns hostname:seqno for consensus bootstrap.
# Peers query this to determine which node has the latest data.

DATA_DIR="/var/lib/mysql"
GRASTATE="${DATA_DIR}/grastate.dat"

# Consume HTTP request headers
while IFS= read -r -t 0.2 line 2>/dev/null; do
  line="${line%$'\r'}"
  [ -z "$line" ] && break
done

seqno="-1"
if [ -f "$GRASTATE" ]; then
  val=$(awk -F: '/^seqno:/{gsub(/[[:space:]]/, "", $2); print $2}' "$GRASTATE" 2>/dev/null || echo "-1")
  [ -n "$val" ] && seqno="$val"
fi

body="$(hostname):${seqno}"
printf 'HTTP/1.0 200 OK\r\nContent-Length: %s\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s' \
  "${#body}" "$body"

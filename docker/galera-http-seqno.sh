#!/usr/bin/env bash
# HTTP endpoint that returns hostname:seqno for consensus bootstrap.
# Peers query this to determine which node has the latest data.

set -euo pipefail

# shellcheck source=galera-http-lib.sh
source "$(dirname "$0")/galera-http-lib.sh"

GRASTATE="${DATA_DIR}/grastate.dat"

consume_http_request

seqno="-1"
if [ -f "$GRASTATE" ]; then
  val=$(awk -F: '/^seqno:/{gsub(/[[:space:]]/, "", $2); print $2}' "$GRASTATE" 2>/dev/null || echo "-1")
  [ -n "$val" ] && seqno="$val"
fi

http_response "200 OK" "$(hostname):${seqno}"

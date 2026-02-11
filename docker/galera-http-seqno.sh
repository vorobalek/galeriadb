#!/usr/bin/env bash
# HTTP endpoint that returns hostname:seqno for consensus bootstrap.
# Peers query this to determine which node has the latest data.

set -euo pipefail

# shellcheck source=galera-http-lib.sh
source "$(dirname "$0")/galera-http-lib.sh"

consume_http_request

seqno=$(read_local_seqno)

http_response "200 OK" "$(hostname):${seqno}"

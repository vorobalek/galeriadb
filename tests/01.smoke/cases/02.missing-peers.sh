#!/usr/bin/env bash
# Smoke case: GALERIA_PEERS missing — container must exit with error (no default).
# Expects: IMAGE (00.common.sh provides expect_required_var_fail).

set -euo pipefail

log "Case 02.missing-peers: container must fail when GALERIA_PEERS is not set"

expect_required_var_fail GALERIA_PEERS \
  -e GALERIA_ROOT_PASSWORD=secret \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1

log "Case 02.missing-peers passed."

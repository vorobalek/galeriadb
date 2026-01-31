#!/usr/bin/env bash
set -euo pipefail

log "Case 02.missing-peers: container must fail when GALERIA_PEERS is not set"

expect_required_var_fail GALERIA_PEERS \
  -e GALERIA_ROOT_PASSWORD=secret \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1

log "Case 02.missing-peers passed."

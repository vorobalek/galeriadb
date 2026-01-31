#!/usr/bin/env bash
set -euo pipefail

log "Case 03.missing-root-password: container must fail when GALERIA_ROOT_PASSWORD is not set"

expect_required_var_fail GALERIA_ROOT_PASSWORD \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1

log "Case 03.missing-root-password passed."

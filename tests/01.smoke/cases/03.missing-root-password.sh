#!/usr/bin/env bash
# Smoke case: GALERIA_ROOT_PASSWORD missing — container must exit with error (no default).
# Expects: IMAGE (00.common.sh provides expect_required_var_fail).

set -euo pipefail

log "Case 03.missing-root-password: container must fail when GALERIA_ROOT_PASSWORD is not set"

expect_required_var_fail GALERIA_ROOT_PASSWORD \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_BOOTSTRAP_CANDIDATE=galera1

log "Case 03.missing-root-password passed."

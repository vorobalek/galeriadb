#!/usr/bin/env bash
# Smoke case: GALERIA_BOOTSTRAP_CANDIDATE missing — container must exit with error (no default).
# Expects: IMAGE (00.common.sh provides expect_required_var_fail).

set -euo pipefail

log "Case 04.missing-bootstrap-candidate: container must fail when GALERIA_BOOTSTRAP_CANDIDATE is not set"

expect_required_var_fail GALERIA_BOOTSTRAP_CANDIDATE \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_ROOT_PASSWORD=secret

log "Case 04.missing-bootstrap-candidate passed."

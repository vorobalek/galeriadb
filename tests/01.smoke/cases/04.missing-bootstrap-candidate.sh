#!/usr/bin/env bash
set -euo pipefail

log "Case 04.missing-bootstrap-candidate: container must fail when GALERIA_BOOTSTRAP_CANDIDATE is not set"

expect_required_var_fail GALERIA_BOOTSTRAP_CANDIDATE \
  -e GALERIA_PEERS=galera1 \
  -e GALERIA_ROOT_PASSWORD=secret

log "Case 04.missing-bootstrap-candidate passed."

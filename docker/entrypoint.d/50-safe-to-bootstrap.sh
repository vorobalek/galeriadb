#!/usr/bin/env bash

if [ "${AM_I_BOOTSTRAP:-0}" = "1" ]; then
  GRASTATE="${DATA_DIR}/grastate.dat"
  if [ -f "$GRASTATE" ] && grep -q "safe_to_bootstrap: 0" "$GRASTATE"; then
    log "Setting safe_to_bootstrap=1 in grastate.dat"
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "$GRASTATE"
  fi
fi

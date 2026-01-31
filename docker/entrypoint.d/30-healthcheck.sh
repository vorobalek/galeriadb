#!/usr/bin/env bash

socat -T 2 TCP-LISTEN:9200,reuseaddr,fork SYSTEM:"${SCRIPT_DIR}/galera-healthcheck.sh" 2>/dev/null &

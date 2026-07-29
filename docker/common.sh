#!/usr/bin/env bash
# Helpers shared by the entrypoint and the health check.

# True while a state snapshot transfer runs on this node. MariaDB keeps the
# wsrep_sst_<method> helper alive for the whole transfer, so a matching process
# means the server is busy receiving data, not stuck.
sst_in_progress() {
  local proc cmdline
  for proc in /proc/[0-9]*/cmdline; do
    cmdline="$(tr '\0' ' ' 2>/dev/null <"$proc")" || continue
    case "$cmdline" in
      *wsrep_sst_*) return 0 ;;
    esac
  done
  return 1
}

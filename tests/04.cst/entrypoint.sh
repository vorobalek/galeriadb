#!/usr/bin/env bash
# Container Structure Test runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config/cst.yaml"
IMAGE="${1:-galeriadb/11.8:local}"

docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "Image $IMAGE not found. Run 'make build' first." >&2
  exit 1
}

if [ ! -f "$CONFIG" ]; then
  echo "CST config not found: $CONFIG" >&2
  exit 1
fi

if ! command -v container-structure-test >/dev/null 2>&1; then
  echo "container-structure-test not found on PATH" >&2
  exit 1
fi

exec container-structure-test test --config "$CONFIG" --image "$IMAGE"

#!/usr/bin/env bash
# Verify that every file COPY'd in the Dockerfile is tested in cst.yaml.
# Run as part of `make lint` to catch drift early.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"
DOCKER_DIR="${REPO_ROOT}/docker"
CST_CONFIG="${REPO_ROOT}/tests/04.cst/config/cst.yaml"

# Files that are intentionally not checked in cst.yaml (add paths here to exclude).
EXCLUDE=()

is_excluded() {
  local path="$1"
  for ex in "${EXCLUDE[@]+"${EXCLUDE[@]}"}"; do
    [ "$path" = "$ex" ] && return 0
  done
  return 1
}

# Build expected file list from Dockerfile COPY instructions.
expected=()
while IFS= read -r line; do
  src=$(echo "$line" | awk '{print $2}')
  dest=$(echo "$line" | awk '{print $3}')

  if [[ "$src" == */ ]]; then
    # Directory copy — enumerate actual files.
    local_dir="${DOCKER_DIR}/${src}"
    for f in "$local_dir"*; do
      [ -f "$f" ] || continue
      expected+=("${dest}$(basename "$f")")
    done
  else
    expected+=("$dest")
  fi
done < <(grep '^COPY ' "$DOCKERFILE")

# Extract paths from cst.yaml fileExistenceTests.
cst_paths=$(grep 'path:' "$CST_CONFIG" | sed 's/.*path: *"//; s/".*//')

# Compare.
rc=0
for exp in "${expected[@]}"; do
  is_excluded "$exp" && continue
  if ! echo "$cst_paths" | grep -qxF "$exp"; then
    echo "MISSING in cst.yaml: $exp" >&2
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  echo "ERROR: Some COPY'd files are not covered by cst.yaml fileExistenceTests." >&2
  echo "Add them to tests/04.cst/config/cst.yaml or exclude in $0." >&2
  exit 1
fi

echo "CST coverage OK: all ${#expected[@]} COPY'd files are checked."

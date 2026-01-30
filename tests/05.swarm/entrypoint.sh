#!/usr/bin/env bash
# Swarm sanity test: init swarm, deploy stack, wait, cleanup.
# Usage: IMAGE=galeriadb/11.8:tag ./tests/05.swarm/entrypoint.sh
# Expects: IMAGE set; image must exist (run 'make build' first with same IMAGE).

set -e

IMAGE="${IMAGE:?IMAGE must be set}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }

log "Swarm sanity: image $IMAGE"

sudo mkdir -p /data/shared/mariadb /data/mariadb
sudo cp examples/docker-swarm/haproxy.cfg /data/shared/mariadb/

NODE=$(docker node ls -q 2>/dev/null | head -1 || true)
if [ -z "$NODE" ]; then
  docker swarm init
  NODE=$(docker node ls -q | head -1)
fi
NODE_HOSTNAME=$(docker node inspect "$NODE" --format '{{.Description.Hostname}}')
sudo mkdir -p /data/mariadb/"$NODE_HOSTNAME"
sudo chmod -R 777 /data/mariadb /data/shared/mariadb

cp examples/docker-swarm/stack.env.example examples/docker-swarm/stack.env 2>/dev/null || true
{
  echo 'GALERIA_ROOT_PASSWORD=secret'
  echo 'GALERIA_PEERS=tasks.galera'
  echo 'GALERIA_CLUSTER_NAME=galera_cluster'
  echo "GALERIA_BOOTSTRAP_CANDIDATE=galera-$NODE_HOSTNAME"
} >examples/docker-swarm/stack.env

cleanup() {
  log "Swarm cleanup"
  docker stack rm mariadb 2>/dev/null || true
  # Poll until stack is gone (no fixed sleep).
  local elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    if ! docker stack services mariadb 2>/dev/null | grep -q .; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  docker swarm leave --force 2>/dev/null || true
}
trap cleanup EXIT

cd examples/docker-swarm
# Compose uses ${IMAGE:-galeriadb/11.8:latest}; we set IMAGE for our test build
export IMAGE
docker stack deploy -c docker-compose.yml mariadb
# Galera is global: one task per node. Expect N/N where N = number of nodes.
expected_replicas=$(docker node ls -q 2>/dev/null | wc -l | tr -d ' ')
log "Waiting for mariadb_galera $expected_replicas/$expected_replicas replicas (up to 90s)..."
elapsed=0
while [ "$elapsed" -lt 90 ]; do
  replicas=$(docker service ls --format '{{.Replicas}}' -f name=mariadb_galera 2>/dev/null | head -1 || echo "")
  if [ "$replicas" = "${expected_replicas}/${expected_replicas}" ]; then
    log "mariadb_galera $replicas"
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if [ "$replicas" != "${expected_replicas}/${expected_replicas}" ]; then
  log "mariadb_galera did not reach $expected_replicas/$expected_replicas (got $replicas)"
  docker service ls
  exit 1
fi
docker service ls
docker service ps mariadb_galera mariadb_hamariadb --no-trunc 2>/dev/null || true

log "Swarm sanity OK"

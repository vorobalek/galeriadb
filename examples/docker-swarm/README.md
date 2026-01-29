# Docker Swarm example

Example stack for MariaDB Galera Cluster behind HAProxy on Docker Swarm. Uses a single overlay network; no external networks required.

## Prerequisites

- Docker Swarm with at least 3 nodes.
- Node hostnames: **node-a**, **node-b**, **node-c** (so that `galera-{{.Node.Hostname}}` becomes `galera-node-a`, etc., and HAProxy server names resolve).
- HAProxy config at `/data/shared/mariadb/haproxy.cfg` on each node (copy from `haproxy.cfg` in this directory).
- Galera data dirs on each node: `/data/mariadb/node-a`, `/data/mariadb/node-b`, `/data/mariadb/node-c` (or adjust the volume path in the stack).

## Setup

1. Copy and edit env file:

   ```bash
   cp stack.env.example stack.env
   # Edit stack.env: set GALERIA_ROOT_PASSWORD (and exporter password if needed).
   ```

2. On each Swarm node, create the HAProxy config path and copy `haproxy.cfg`:

   ```bash
   sudo mkdir -p /data/shared/mariadb
   sudo cp haproxy.cfg /data/shared/mariadb/haproxy.cfg
   ```

3. On each node, create the Galera data directory (e.g. for hostname `node-a`):

   ```bash
   sudo mkdir -p /data/mariadb/$(hostname)
   ```

4. Deploy the stack from the directory that contains both `docker-compose.yml` and `stack.env`:

   ```bash
   docker stack deploy -c docker-compose.yml mariadb
   ```

   Connect to the cluster via any node at **3306** (HAProxy); stats at **7000**; mysqld-exporter metrics at **9090**.

5. (Optional) Create `monitoring` user in MariaDB for mysqld-exporter and set its password in `stack.env` if your exporter image expects it.

## Files

- **docker-compose.yml** — Stack definition (hamariadb, galera, mariadb-exporter).
- **haproxy.cfg** — HAProxy config; place at `/data/shared/mariadb/haproxy.cfg` (or update the volume path in the stack).
- **stack.env.example** — Template for `stack.env` (passwords, peers, cluster name).

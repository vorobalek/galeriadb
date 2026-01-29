# galeriadb

Docker image for **MariaDB + Galera Cluster**, suitable for Docker Compose and Docker Swarm. Supports arbitrary node startup order (bootstrap/join without `depends_on`), HAProxy health checks, and a single client endpoint.

- [MariaDB Galera Cluster Guide](https://mariadb.com/docs/galera-cluster/galera-cluster-quickstart-guides/mariadb-galera-cluster-guide)

## Image

- **Docker Hub:** `galeriadb/10.11`
- **Tag:** `latest` (image name is the MariaDB version, e.g. `galeriadb/10.11:latest`)

Built and published via [GitHub Actions](.github/workflows/docker-publish.yml) on push to `main`. Repository secrets required: `DOCKER_USERNAME`, `DOCKER_PASSWORD` (Docker Hub account used for publishing).

## Quick start (example)

From the `examples/` directory:

```bash
cd examples
docker compose up -d
```

Connect to the cluster via HAProxy on port **3306**:

- **Host:** `localhost`
- **Port:** `3306`
- **User:** `root`
- **Password:** `secret` (set in `examples/docker-compose.yml`)

```bash
mariadb -h 127.0.0.1 -P 3306 -u root -psecret
```

## Environment variables

| Variable | Description | Example |
|----------|-------------|---------|
| `MYSQL_ROOT_PASSWORD` | Password for `root` user | `secret` |
| `GALERA_PEERS` | Comma-separated node hostnames (Compose) | `galera1,galera2,galera3` |
| `WSREP_CLUSTER_NAME` | Cluster name | `galera_cluster` |
| `SERVICE_NAME` | Service name for Swarm DNS (`tasks.$SERVICE_NAME`) | `mariadb` |

In Swarm you can omit `GALERA_PEERS`; nodes are discovered via `tasks.$SERVICE_NAME`.

## Ports

- **3306** — MariaDB (clients)
- **4567** — Galera replication
- **4568** — IST
- **4444** — SST
- **9200** — HTTP health check (wsrep_ready=ON, Synced) for HAProxy

## Building the image locally

```bash
docker build -t galeriadb/10.11:latest -f docker/Dockerfile docker/
```

## Repository structure

- `docker/` — Dockerfile and build context (entrypoint, Galera config, health check).
- `examples/` — sample `docker-compose` stack (image `galeriadb/10.11:latest`) with three Galera nodes and HAProxy.

## License

MIT

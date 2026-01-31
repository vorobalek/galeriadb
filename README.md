# galeriadb

Docker image for MariaDB + Galera Cluster. Designed for Compose and Swarm, supports arbitrary node startup order, and exposes an HTTP health check for HAProxy.

- [MariaDB Galera Cluster Guide](https://mariadb.com/docs/galera-cluster/galera-cluster-quickstart-guides/mariadb-galera-cluster-guide)

## Image

- Docker Hub: `galeriadb/11.8`
- Tag: `latest` (image name encodes MariaDB version, e.g. `galeriadb/11.8:latest`)

## Features

- Cluster discovery from `GALERIA_PEERS` with bootstrap candidate logic.
- HAProxy-friendly health check on port 9200 (Synced + wsrep_ready=ON).
- Hot backups to S3 with optional retention and cron scheduling.
- Restore (clone) from S3 when the data directory is empty.

## Quick start

From the example Compose stack:

```bash
cd examples/docker-compose
docker compose up -d
```

Connect via HAProxy on port 3306:

```bash
mariadb -h 127.0.0.1 -P 3306 -u root -psecret
```

## Configuration

### Required

The container exits immediately if any required variable is missing or empty.

| Variable | Description | Example |
| --- | --- | --- |
| `GALERIA_PEERS` | Comma-separated peer list. Use Compose service names, Swarm task names (`tasks.galera`), or IPs/hostnames. | `galera1,galera2,galera3` / `tasks.galera` / `10.0.0.1,10.0.0.2` |
| `GALERIA_ROOT_PASSWORD` | Password for MariaDB `root` user (no default). | `secret` |
| `GALERIA_BOOTSTRAP_CANDIDATE` | Hostname of the node that may bootstrap a new cluster when none is found. Must match one of your node hostnames. | `galera1` |

### Cluster and discovery

| Variable | Description | Default |
| --- | --- | --- |
| `GALERIA_CLUSTER_NAME` | Galera cluster name (`wsrep_cluster_name`). | `galera_cluster` |
| `GALERIA_DISCOVERY_TIMEOUT` | Total seconds to resolve peers before continuing. | `5` |
| `GALERIA_DISCOVERY_INTERVAL` | Seconds between resolution attempts. | `1` |
| `GALERIA_NODE_ADDRESS` | Override this node's IP address if auto-detection is wrong. | auto-detected |

Discovery behavior:

- The image resolves `GALERIA_PEERS` and looks for a Synced node.
- If a Synced node is found, this node joins it.
- If none is found within the discovery window, only the bootstrap candidate starts a new cluster; other nodes join and wait for primary.
- In Swarm or Kubernetes, peer DNS may be empty during the first task start. The discovery window avoids long waits while still allowing late joiners.

### Health check

The image starts an HTTP listener on port 9200 and returns 200 only when the node is Synced and `wsrep_ready=ON`.

Optional:

| Variable | Description | Default |
| --- | --- | --- |
| `GALERIA_HEALTHCHECK_USER` | MySQL user for health check queries. | `root` |
| `GALERIA_HEALTHCHECK_PASSWORD` | Password for health check user. | `GALERIA_ROOT_PASSWORD` |

If both `GALERIA_HEALTHCHECK_USER` and `GALERIA_HEALTHCHECK_PASSWORD` are set and the user is not `root`, the entrypoint will create/update that user and grant the minimal permissions required for the check.

### Backups to S3

Hot backups run only on nodes in Synced state.

| Variable | Description | Default |
| --- | --- | --- |
| `GALERIA_BACKUP_SCHEDULE` | Cron schedule for backups. Empty disables cron. | empty |
| `GALERIA_BACKUP_S3_URI` | Full S3 URI for backups (overrides bucket+path). | — |
| `GALERIA_BACKUP_S3_BUCKET` | S3 bucket name. | — |
| `GALERIA_BACKUP_S3_PATH` | Path under bucket if using `GALERIA_BACKUP_S3_BUCKET`. | `mariadb` |
| `GALERIA_BACKUP_TMPDIR` | Temporary directory for backups. | `/tmp` |
| `GALERIA_BACKUP_RETENTION_DAYS` | Delete backups older than this many days (by S3 LastModified). | — |
| `GALERIA_BACKUP_RETENTION_CUTOFF_OVERRIDE` | Override retention cutoff date (YYYY-MM-DD). Useful for tests. | — |
| `GALERIA_CRONTAB` | Additional cron lines to install alongside backups. | — |
| `AWS_ACCESS_KEY_ID` | AWS access key (optional if using IAM role). | — |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key. | — |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | AWS region for S3. | — |
| `AWS_ENDPOINT_URL` | Custom S3 endpoint (e.g. MinIO). | — |

Manual backup:

```bash
docker exec <container> /usr/local/bin/galera-backup.sh
```

Backup logs are written to `/var/log/galera-backup.log` inside the container.

### Restore (clone) from S3

Restore runs only when `/var/lib/mysql` is empty on container startup and clone variables are set.

| Variable | Description | Default |
| --- | --- | --- |
| `GALERIA_CLONE_BACKUP_S3_URI` | Full S3 URI for restore (overrides bucket+path). | — |
| `GALERIA_CLONE_BACKUP_S3_BUCKET` | S3 bucket name. | — |
| `GALERIA_CLONE_BACKUP_S3_PATH` | Path under bucket if using `GALERIA_CLONE_BACKUP_S3_BUCKET`. | `mariadb` |
| `GALERIA_CLONE_FROM` | Object key relative to base path or full `s3://` URI. If unset, the latest backup under `{hostname}/` is used. | — |
| `GALERIA_CLONE_TMPDIR` | Temporary directory for restore files. | `/tmp` |
| `CLONE_AWS_ACCESS_KEY_ID` | AWS access key for restore. | — |
| `CLONE_AWS_SECRET_ACCESS_KEY` | AWS secret key for restore. | — |
| `CLONE_AWS_SESSION_TOKEN` | AWS session token (optional). | — |
| `CLONE_AWS_REGION` / `CLONE_AWS_DEFAULT_REGION` | AWS region for restore. | — |
| `CLONE_AWS_ENDPOINT_URL` | Custom S3 endpoint (e.g. MinIO). | — |

### Behavior notes

- `root@%` is created on startup and granted full privileges.
- If the node is the bootstrap candidate, `safe_to_bootstrap` is set to 1 in `grastate.dat` when needed.

## Ports

- 3306 - MariaDB clients
- 4567 - Galera replication
- 4568 - IST
- 4444 - SST
- 9200 - HTTP health check

## Build

```bash
docker build -t galeriadb/11.8:latest -f docker/Dockerfile docker/
```

## Tests

Single entry point:

```bash
make ci
```

Run inside the dev container (no local toolchain required):

```bash
make ci-docker
```

Targets:

| Command | Description |
| --- | --- |
| `make ci` | lint, build, CST, security, smoke, deploy, backup-s3 |
| `make ci-docker` | same as `make ci` inside dev container |
| `make lint` | hadolint, shellcheck, shfmt |
| `make lint-docker` | lint inside dev container |
| `make build` | build image (`galeriadb/11.8:local`) |
| `make cst` | Container Structure Tests |
| `make security` | Trivy (CRITICAL) + Dockle |
| `make smoke` | required env validation + single-node startup |
| `make deploy` | 3-node Galera + HAProxy scenarios |
| `make backup-s3` | S3 backup tests (MinIO) |
| `make swarm` | Swarm sanity (run after `make ci`) |

Tests live in `tests/00.*` through `tests/05.*`. Each test directory has its own `entrypoint.sh`. Diagnostics are written to `./artifacts/` on failure.

## CI and publishing

GitHub Actions runs `make ci` in a dev container on pull requests to the `11.8` branch and on manual runs. The Swarm job runs on the same triggers after CI passes (unless `[skip-ci]` is set).

Images are built and published via `.github/workflows/docker-publish.yml` on push to `11.8` and on manual runs (skips when `[skip-ci]` is in the head commit message). Required secrets: `DOCKER_USERNAME`, `DOCKER_PASSWORD`.

## Repository layout

- `docker/` - Dockerfile, entrypoint, entrypoint stages, backup/clone scripts, templates.
- `tests/` - CI and local test suite.
- `examples/docker-compose/` - local Compose stack (3 nodes + HAProxy).
- `examples/docker-swarm/` - Swarm stack and docs.

## License

This repository is licensed under the MIT License. The image includes third-party software (MariaDB, Galera, socat, etc.) under their own licenses; see `NOTICE` for details.

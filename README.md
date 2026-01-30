# galeriadb

Docker image for **MariaDB + Galera Cluster**, suitable for Docker Compose and Docker Swarm. Supports arbitrary node startup order (bootstrap/join without `depends_on`), HAProxy health checks, and a single client endpoint.

- [MariaDB Galera Cluster Guide](https://mariadb.com/docs/galera-cluster/galera-cluster-quickstart-guides/mariadb-galera-cluster-guide)

## Image

- **Docker Hub:** `galeriadb/11.8`
- **Tag:** `latest` (image name is the MariaDB version, e.g. `galeriadb/11.8:latest`)

Built and published via [GitHub Actions](.github/workflows/docker-publish.yml) on push to `main`. Repository secrets required: `DOCKER_USERNAME`, `DOCKER_PASSWORD` (Docker Hub account used for publishing).

## Quick start (example)

**Docker Compose** — from the `examples/docker-compose/` directory:

```bash
cd examples/docker-compose
docker compose up -d
```

Connect to the cluster via HAProxy on port **3306**:

- **Host:** `localhost`
- **Port:** `3306`
- **User:** `root`
- **Password:** `secret` (value of `GALERIA_ROOT_PASSWORD` in the example)

```bash
mariadb -h 127.0.0.1 -P 3306 -u root -psecret
```

## Environment variables

### Cluster

| Variable | Description | Example |
|----------|-------------|---------|
| `GALERIA_ROOT_PASSWORD` | Password for MariaDB `root` user | `secret` |
| `GALERIA_PEERS` | Comma-separated peer list: Compose service names, Swarm task names (e.g. `tasks.galera`), or IPs/hostnames. Used as the only source for cluster member discovery. | `galera1,galera2,galera3` or `tasks.galera` or `10.0.0.1,10.0.0.2,10.0.0.3` |
| `GALERIA_CLUSTER_NAME` | Galera cluster identifier (`wsrep_cluster_name`). Nodes with the same name form one cluster; different names do not join. | `galera_cluster` |
| `GALERIA_RESOLVE_RETRIES` | Number of retries when resolving peers (Swarm/K8s: DNS may not be ready at startup). Default `6`. | `6` |
| `GALERIA_RESOLVE_INTERVAL` | Seconds between retries. Default `5`. | `5` |

### Hot backup to S3

Hot backups run only on nodes in **Synced** state. To enable scheduled backups, set `GALERIA_BACKUP_SCHEDULE` and either `GALERIA_BACKUP_S3_URI` or `GALERIA_BACKUP_S3_BUCKET`.

| Variable | Description | Example |
|----------|-------------|---------|
| `GALERIA_BACKUP_SCHEDULE` | Cron expression for backup job. If empty, scheduled backups are disabled. | `0 1 * * *` (daily at 01:00 UTC) |
| `GALERIA_BACKUP_S3_URI` | Full S3 URI for backups (overrides bucket+path when set). | `s3://my-bucket/mariadb` |
| `GALERIA_BACKUP_S3_BUCKET` | S3 bucket name; path under bucket uses `GALERIA_BACKUP_S3_PATH`. Alternative to full URI. | `my-bucket` |
| `GALERIA_BACKUP_S3_PATH` | Path under bucket when using `GALERIA_BACKUP_S3_BUCKET`. Default `mariadb`. | `backups/mariadb` |
| `GALERIA_BACKUP_TMPDIR` | Directory for temporary backup files. Default `/tmp`. | `/var/lib/mysql/tmp` |
| `GALERIA_BACKUP_RETENTION_DAYS` | Delete backups older than this many days (optional). | `7` |
| `GALERIA_CRONTAB` | Extra cron lines (e.g. additional jobs). Applied together with backup schedule. | — |
| `AWS_ACCESS_KEY_ID` | AWS access key (optional if using IAM role / instance profile). | — |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key (optional if using IAM role). | — |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | AWS region for S3. | `eu-west-1` |
| `AWS_ENDPOINT_URL` | Custom S3 endpoint (e.g. MinIO). | `https://s3.example.com` |

Manual run: `docker exec <container> /usr/local/bin/galera-backup.sh`. Logs: `/var/log/galera-backup.log` inside the container.

In Swarm or Kubernetes, peer DNS (e.g. `tasks.galera`) is often empty when the first task starts. If no other peers resolve after retries, the node bootstraps a new cluster; later tasks will resolve and join. This avoids deadlock where every task waits for others to appear in DNS.

## Ports

- **3306** — MariaDB (clients)
- **4567** — Galera replication
- **4568** — IST
- **4444** — SST
- **9200** — HTTP health check (wsrep_ready=ON, Synced) for HAProxy

## Building the image locally

```bash
docker build -t galeriadb/11.8:latest -f docker/Dockerfile docker/
```

## Testing locally

**Dependencies:** Docker, Docker Compose. For full checks: [hadolint](https://github.com/hadolint/hadolint), [ShellCheck](https://www.shellcheck.net/), [shfmt](https://github.com/mvdan/sh), [container-structure-test](https://github.com/GoogleContainerTools/container-structure-test), [Trivy](https://github.com/aquasecurity/trivy), [Dockle](https://github.com/goodwithtech/dockle).

Run all tests (lint, build, structure tests, security, smoke, integration):

```bash
make test
```

Individual targets:

| Command | Description |
|---------|-------------|
| `make lint` | Hadolint (Dockerfile), ShellCheck and shfmt (shell scripts) |
| `make build` | Build image `galeriadb/11.8:local` |
| `make cst` | Container Structure Tests (files, ports, commands) |
| `make security` | Trivy (CRITICAL) + Dockle (best practices) |
| `make smoke` | Single-container smoke test (readiness, `SELECT 1`) |
| `make integration` | 3-node Galera + HAProxy (all cases: 01.all, 02.mixed, 03.restart) |
| `make integration-mixed` | Same stack, case 02.mixed only (staggered start) |
| `make integration-restart` | Same stack, case 03.restart only (restart node) |
| `make backup-s3` | S3 backup test (cases: 01.backup-to-s3, 02.fail-without-s3-config) |

Tests live in numbered dirs: `00.*` = shared (lib, config), `01.*`–`04.*` = tests by importance. Each test dir has `entrypoint.sh` and assets in subdirs; tests with multiple scenarios use a `cases/` subdir (`00.*` = common, `01.*`, `02.*`, … = scenario scripts). **All tests use the locally built image** when run via `make` (default tag `galeriadb/11.8:local`). Run `make build` before running scripts directly.

```bash
make build   # builds galeriadb/11.8:local
./tests/01.smoke/entrypoint.sh
./tests/02.integration-compose/entrypoint.sh                    # all cases
./tests/02.integration-compose/entrypoint.sh "" 02.mixed       # one case
./tests/03.backup-s3/entrypoint.sh
./tests/03.backup-s3/entrypoint.sh "" 01.backup-to-s3          # one case
./tests/04.cst/entrypoint.sh
# Or pass image: ./tests/01.smoke/entrypoint.sh galeriadb/11.8:latest
```

On failure, integration tests write diagnostics to `./artifacts/` (docker ps, compose logs, inspect).

## CI overview

GitHub Actions workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on:

- **Pull requests** and **push to main**
- **Manual** (`workflow_dispatch`)
- **Nightly** (schedule)

**Layers:**

| Layer | PR / main | Nightly |
|-------|-----------|---------|
| Lint | hadolint, shellcheck, shfmt | same |
| Build | Build image (BuildKit cache) | same |
| Container Structure Test | Files, ports, entrypoint, commands | same |
| Security | Trivy CRITICAL; on main also HIGH. Dockle (best practices) | same |
| Smoke | One container, readiness, `SELECT 1` | same |
| Integration | 3 nodes + HAProxy, replication, HAProxy endpoint | same |
| Integration (mixed/restart) | — | mixed order + restart-node scenarios |
| S3 backup (MinIO) | Hot backup to MinIO, verify object | same |
| Swarm sanity | — | Single-node swarm, stack deploy |

On **PR**: one integration scenario (all nodes up, replication + HAProxy). On **main** and **nightly**: all integration scenarios and optional Swarm sanity.

**Troubleshooting CI:** If a job fails, open the run → **Summary** → **Artifacts**. Download `ci-diagnostics` for `docker-ps.txt`, `compose-logs.txt`, `inspect-*.json`, and network/volume lists from the failing step.

## Repository structure

- `docker/` — Dockerfile and build context (entrypoint, discovery, config, health check, backup scripts).
- `tests/` — Test suite: each test in its own dir with `entrypoint.sh` and assets (see below).
- `examples/docker-compose/` — sample Compose stack (three Galera nodes + HAProxy) for local testing.
- `examples/docker-swarm/` — sample Swarm stack (global Galera + HAProxy + optional mysqld-exporter); see `examples/docker-swarm/README.md`.

**Test layout:** `tests/00.lib/` (common.sh), `tests/00.config/` (dockle.yaml); then tests by importance: `01.smoke/`, `02.integration-compose/` (compose/, cases/01.all 02.mixed 03.restart), `03.backup-s3/` (cases/01.backup-to-s3 02.fail-without-s3-config), `04.cst/` (config/cst.yaml). Each test dir has `entrypoint.sh`; multi-scenario tests use `cases/` with `00.*` for common and `01.*`, `02.*`, … for scenario scripts.

## License

This repository's code is licensed under the [MIT License](LICENSE).

The Docker image built from this repo includes third-party software (MariaDB, Galera, socat, etc.) under their own licenses, notably GPL v2. See [NOTICE](NOTICE) for a list of components, their licenses, and source links.

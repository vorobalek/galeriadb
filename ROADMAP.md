# Roadmap

## TLS Everywhere

- **wsrep SSL** — encrypt replication traffic between nodes (`wsrep_provider_options="socket.ssl_*"`)
- **Client SSL** — encrypt client connections
- Auto-generate self-signed certificates on first start (similar to MySQL 8)
- Or mount existing certificates via volume + `GALERIA_SSL_*` variables

## Readiness vs Liveness — Two Separate Endpoints

Currently there is a single healthcheck on port 9200. In Kubernetes/Swarm these serve different
purposes:

| Endpoint | Logic | Purpose |
|----------|-------|---------|
| `/live` | mariadbd process is alive | Liveness — restart on hang |
| `/ready` | Synced + wsrep_ready=ON | Readiness — traffic routing |
| `/donor` | Donor/Desynced state | Specific scenarios (read from donor) |

## Auto-tuning Based on cgroup Limits

Automatic InnoDB tuning based on available container memory:

```bash
mem=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
# innodb_buffer_pool_size = 70% of limit
# innodb_log_file_size = 25% of buffer_pool
# wsrep gcache.size = proportional
```

Controlled by `GALERIA_AUTO_TUNE=on|off` with per-parameter overrides.

## Incremental Backups + Point-in-Time Recovery

Currently only full backups are supported. Possible additions:

- **Incremental backups** via `mariadb-backup --incremental` (chain: full → inc1 → inc2)
- **Binlog shipping to S3** — continuous upload of binary logs
- Restore to an arbitrary point in time: `GALERIA_CLONE_PITR="2026-02-11 14:30:00"`

## Init Scripts (`/docker-entrypoint-initdb.d/`)

A pattern familiar from the official MySQL/MariaDB images:

- Mount `.sql`, `.sh`, or `.sql.gz` files into this directory
- On first initialization they are executed on the bootstrap node only
- Bootstrap-only execution prevents duplication

## Docker Secrets Instead of Environment Variables

Currently passwords are passed via env vars (visible in `docker inspect`). Support file-based
secrets:

```bash
# Read password from file when the variable points to a file
GALERIA_ROOT_PASSWORD_FILE=/run/secrets/db_root_password
```

The `*_FILE` pattern is the standard for official Docker images.

## Backup Verification

After each backup (or on a schedule):

- Download the latest backup from S3
- Run `mariadb-backup --prepare` in a temporary directory
- Verify integrity
- Report result as a metric
- Clean up temporary files

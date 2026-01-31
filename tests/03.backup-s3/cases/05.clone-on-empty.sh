#!/usr/bin/env bash
# Case: restore from S3 backup when data dir is empty on startup.
# Sourced from entrypoint. Uses 00.common.sh helpers.

log "Case 05.clone-on-empty: restore from S3 when /var/lib/mysql is empty"
# Clean up any containers from previous cases
docker rm -f "$GALERA_NAME" 2>/dev/null || true
docker rm -f "$MINIO_NAME" 2>/dev/null || true

start_minio
start_galera
wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}
wait_synced || {
  docker logs "$GALERA_NAME" 2>&1 | tail -50
  exit 1
}

log "Creating test data..."
docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; DROP TABLE IF EXISTS ci_clone; CREATE TABLE ci_clone (id INT PRIMARY KEY, v VARCHAR(32)); INSERT INTO ci_clone VALUES (1, 'clone-ok');"

log "Creating S3 bucket..."
docker exec "$GALERA_NAME" aws s3 mb "s3://${S3_BUCKET}" 2>/dev/null || true

log "Running galera-backup.sh..."
docker exec -e MYSQL_PWD="$PASS" "$GALERA_NAME" /usr/local/bin/galera-backup.sh || {
  log "galera-backup.sh failed"
  docker logs "$GALERA_NAME" 2>&1 | tail -30
  exit 1
}

log "Restarting with clone enabled..."
docker rm -f "$GALERA_NAME" 2>/dev/null || true
start_galera_clone
wait_mysql_ready || {
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
}

val=$(docker exec "$GALERA_NAME" mariadb -u root -p"$PASS" -Nse "USE testdb; SELECT v FROM ci_clone WHERE id=1" 2>/dev/null || echo "")
if [ "$val" != "clone-ok" ]; then
  log "Restore failed: expected 'clone-ok', got '$val'"
  docker logs "$GALERA_NAME" 2>&1 | tail -80
  exit 1
fi
log "Case 05.clone-on-empty passed."

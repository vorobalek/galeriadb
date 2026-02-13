#!/usr/bin/env bash

DATA_DIR="/var/lib/mysql"
export DATA_DIR

log() { echo "[$(date -Is)] $*"; }

backup_configured() {
  [ -n "${GALERIA_BACKUP_S3_URI:-}" ] || [ -n "${GALERIA_BACKUP_S3_BUCKET:-}" ]
}

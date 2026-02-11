#!/usr/bin/env bash

DATA_DIR="/var/lib/mysql"
export DATA_DIR

log() { echo "[$(date -Is)] $*"; }

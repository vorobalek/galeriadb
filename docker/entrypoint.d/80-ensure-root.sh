#!/usr/bin/env bash

ROOT_SQL="CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${GALERIA_ROOT_PASSWORD}';
GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
mariadb -u root -e "$ROOT_SQL" 2>/dev/null || true

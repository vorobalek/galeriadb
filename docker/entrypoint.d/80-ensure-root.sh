#!/usr/bin/env bash

# Escape single quotes for SQL: ' -> ''
escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

ROOT_PWD_ESC="$(escape_sql_string "${GALERIA_ROOT_PASSWORD}")"
ROOT_SQL="CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${ROOT_PWD_ESC}';
GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
mariadb -u root -e "$ROOT_SQL" 2>/dev/null || true

if [ -n "${GALERIA_HEALTHCHECK_USER:-}" ] && [ -n "${GALERIA_HEALTHCHECK_PASSWORD:-}" ] && [ "${GALERIA_HEALTHCHECK_USER}" != "root" ]; then
  HC_USER_ESC="$(escape_sql_string "${GALERIA_HEALTHCHECK_USER}")"
  HC_PWD_ESC="$(escape_sql_string "${GALERIA_HEALTHCHECK_PASSWORD}")"
  HEALTH_SQL="CREATE USER IF NOT EXISTS '${HC_USER_ESC}'@'%' IDENTIFIED BY '${HC_PWD_ESC}';
ALTER USER '${HC_USER_ESC}'@'%' IDENTIFIED BY '${HC_PWD_ESC}';
GRANT PROCESS ON *.* TO '${HC_USER_ESC}'@'%';
FLUSH PRIVILEGES;"
  mariadb -u root -e "$HEALTH_SQL" 2>/dev/null || true
fi

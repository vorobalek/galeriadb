#!/usr/bin/env bash

GALERA_CNF="/etc/mysql/mariadb.conf.d/99-galera.cnf"
cp /etc/mysql/conf.d/galera.cnf.template "$GALERA_CNF"
for var in CLUSTER_ADDRESS WSREP_CLUSTER_NAME WSREP_NODE_NAME WSREP_NODE_ADDRESS; do
  val="${!var}"
  [ -z "$val" ] && continue
  val_escaped=$(echo "$val" | sed 's/#/\\#/g; s#/#\\/#g; s#&#\\&#g')
  sed -i "s#{{${var}}}#${val_escaped}#g" "$GALERA_CNF"
done
chmod 660 "$GALERA_CNF"
chown mysql:mysql "$GALERA_CNF"

log "============ galera.cnf ============"
cat "$GALERA_CNF"
log "===================================="

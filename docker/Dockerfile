# MariaDB + Galera Cluster image for Docker Swarm / Docker Compose
# Based on MariaDB Galera Quickstart: https://mariadb.com/docs/galera-cluster/galera-cluster-quickstart-guides/mariadb-galera-cluster-guide

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dirmngr \
    gnupg \
    apt-transport-https \
    software-properties-common \
    rsync \
    gettext-base \
    socat \
    && curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-11.8" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    mariadb-server \
    mariadb-client \
    galera-4 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Galera config template (variables substituted at runtime)
COPY galera.cnf.template /etc/mysql/conf.d/galera.cnf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY galera-healthcheck.sh /usr/local/bin/galera-healthcheck.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/galera-healthcheck.sh \
    && chown -R mysql:mysql /etc/mysql /var/lib/mysql /var/run/mysqld 2>/dev/null || true \
    && mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# 3306 MariaDB, 4567 Galera, 4568 IST, 4444 SST, 9200 health check HTTP
EXPOSE 3306 4567 4568 4444 9200

VOLUME /var/lib/mysql

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

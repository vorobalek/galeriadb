# MariaDB + Galera Cluster image for Docker Swarm / Docker Compose
# Based on MariaDB Galera Quickstart: https://mariadb.com/docs/galera-cluster/galera-cluster-quickstart-guides/mariadb-galera-cluster-guide

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Use bash with pipefail so piped RUN fails if any command in the pipe fails
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Layer 1: base packages (changes rarely) — best cache reuse
# hadolint ignore=DL3008: pinning every apt package is impractical for base image
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    cron \
    dirmngr \
    gnupg \
    apt-transport-https \
    software-properties-common \
    rsync \
    gettext-base \
    socat \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: MariaDB + Galera (rebuilt when DB version changes)
# hadolint ignore=DL3008
RUN apt-get update \
    && curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-11.8" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    mariadb-server \
    mariadb-client \
    mariadb-backup \
    galera-4 \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 3: AWS CLI (rebuilt only when CLI/version changes)
RUN curl -sSfL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -b /usr/local/bin \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && apt-get purge -y unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Galera config template (variables substituted at runtime)
COPY galera.cnf.template /etc/mysql/conf.d/galera.cnf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY galera-discovery.sh /usr/local/bin/galera-discovery.sh
COPY galera-write-config.sh /usr/local/bin/galera-write-config.sh
COPY galera-healthcheck.sh /usr/local/bin/galera-healthcheck.sh
COPY galera-backup.sh /usr/local/bin/galera-backup.sh
COPY galera-backup-setup.sh /usr/local/bin/galera-backup-setup.sh
COPY galera-clone.sh /usr/local/bin/galera-clone.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/galera-discovery.sh /usr/local/bin/galera-write-config.sh /usr/local/bin/galera-healthcheck.sh /usr/local/bin/galera-backup.sh /usr/local/bin/galera-backup-setup.sh /usr/local/bin/galera-clone.sh \
    && chown -R mysql:mysql /etc/mysql /var/lib/mysql /var/run/mysqld 2>/dev/null || true \
    && mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# 3306 MariaDB, 4567 Galera, 4568 IST, 4444 SST, 9200 health check HTTP
EXPOSE 3306 4567 4568 4444 9200

VOLUME /var/lib/mysql

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

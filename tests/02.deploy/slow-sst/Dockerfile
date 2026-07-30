# Image under test with a deliberately slow joiner state transfer.
ARG BASE_IMAGE=galeriadb/11.8:local
FROM ${BASE_IMAGE}

# Replace the script instead of shadowing it through PATH: the server does not
# resolve the SST helper through PATH.
RUN mv /usr/bin/wsrep_sst_rsync /usr/bin/wsrep_sst_rsync.real
COPY wsrep_sst_rsync /usr/bin/wsrep_sst_rsync
RUN chmod +x /usr/bin/wsrep_sst_rsync

# Image under test with a deliberately slow joiner state transfer.
ARG BASE_IMAGE=galeriadb/12.1:local
# The tag comes from BASE_IMAGE, which the test passes in.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

# Replace the script instead of shadowing it through PATH: the server does not
# resolve the SST helper through PATH.
RUN mv /usr/bin/wsrep_sst_rsync /usr/bin/wsrep_sst_rsync.real
COPY wsrep_sst_rsync /usr/bin/wsrep_sst_rsync
RUN chmod +x /usr/bin/wsrep_sst_rsync

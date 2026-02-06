FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    rsync \
    rclone \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install OpenBao CLI (vault CLI is compatible)
# Pinned version with SHA256 verification for security
ARG BAO_VERSION=2.5.0
ARG BAO_SHA256=ec664e934bf77a8dfc389b92605c6fa420216e696bf865daff9a5a356af388d3
RUN curl -fsSL "https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/bao_${BAO_VERSION}_Linux_x86_64.tar.gz" \
    -o /tmp/bao.tar.gz \
    && echo "${BAO_SHA256}  /tmp/bao.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/bao.tar.gz -C /usr/local/bin bao \
    && rm /tmp/bao.tar.gz \
    && chmod +x /usr/local/bin/bao

# Create non-root user and working directory
RUN adduser --uid 1000 --disabled-password --gecos "" backupuser \
    && mkdir -p /opt/backup \
    && chown backupuser:backupuser /opt/backup

COPY --chown=backupuser:backupuser scripts/ /opt/backup/
RUN chmod +x /opt/backup/*.sh

WORKDIR /opt/backup
ENTRYPOINT ["/opt/backup/entrypoint.sh"]
CMD ["bash"]

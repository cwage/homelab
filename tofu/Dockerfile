FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    openssh-client \
    ca-certificates \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install OpenTofu
# Version pinned for reproducibility - update as needed
ENV TOFU_VERSION=1.6.2

RUN wget -O /tmp/tofu.deb \
    "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_amd64.deb" && \
    dpkg -i /tmp/tofu.deb && \
    rm /tmp/tofu.deb

# Verify installation
RUN tofu version

# Create non-root user with UID/GID 1000
RUN groupadd -g 1000 tofu && \
    useradd -u 1000 -g 1000 -m -s /bin/bash tofu

# Set working directory
WORKDIR /workspace
RUN chown tofu:tofu /workspace
# Switch to non-root user
USER tofu

# Default command
CMD ["tofu"]

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-venv \
      ssh openssh-client \
      ca-certificates git \
 && python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir ansible-core==2.16.* \
 && ln -s /opt/venv/bin/ansible /usr/local/bin/ansible \
 && ln -s /opt/venv/bin/ansible-playbook /usr/local/bin/ansible-playbook \
  && ln -s /opt/venv/bin/ansible-galaxy /usr/local/bin/ansible-galaxy \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Create a non-root user with UID/GID 1000 for safer defaults
RUN groupadd -g 1000 nonroot \
 && useradd -m -u 1000 -g 1000 -s /bin/bash nonroot

USER nonroot

# Default to a shell so you can run any ansible command via `docker compose run`
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["ansible --version"]

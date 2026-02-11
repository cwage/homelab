FROM ruby:3.1-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /site

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

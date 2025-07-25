FROM gitpod/workspace-base

USER root

# Install only what you need
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    postgresql-client \
    curl \
    unzip \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Docker Compose manually (latest stable as of 2025)
RUN curl -L "https://github.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose

USER gitpod
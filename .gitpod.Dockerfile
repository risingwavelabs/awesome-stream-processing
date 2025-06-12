FROM gitpod/workspace-full

USER root

#added only needed tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    curl \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*


RUN curl -L "https://github.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

USER gitpod

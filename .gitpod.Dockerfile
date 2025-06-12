FROM gitpod/workspace-full

USER root

RUN apt-get update && apt-get install -y \
    postgresql-client \
    net-tools \
    iputils-ping \
    curl \
    gnupg2 \
    lsb-release \
    unzip \
    && apt-get clean

RUN curl -L "https://github.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose
    
USER gitpod

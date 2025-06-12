FROM gitpod/workspace-full

USER root

RUN apt-get update && apt-get install -y \
    docker-compose \
    postgresql-client \
    net-tools \
    iputils-ping \
    && apt-get clean

USER gitpod
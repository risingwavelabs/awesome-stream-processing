# Install Kafka, RisingWave, and PostgreSQL

If you do not have experience with or have not installed Kafka, RisingWave, or PostgreSQL, follow along to learn how to set up these systems.

## Install Kafka

Apache Kafka is an open-distributed event streaming platform for building event-driven architectures, enabling you to retrieve and process data in real time. 

To install and run the self-hosted version of Kafka, follow steps one through three outlined in this [Apache Kafka quickstart](https://kafka.apache.org/quickstart).

You should have learned how to install Kafka, start the environment, and create a topic. 

## Install PostgreSQL

PostgreSQL is a relational database management system, allowing you to store and manage your data.

To use RisingWave and ingest CDC data from PostgreSQL databases, you will need to install the PostgreSQL server. To learn about the different packages and installers for various platforms, see [PostgreSQL Downloads](https://www.postgresql.org/download/).

## Install RisingWave

RisingWave is an open-source distributed SQL streaming database licensed under the Apache 2.0 license. It utilizes a PostgreSQL-compatible interface, allowing users to perform distributed stream processing in the same way as operating a PostgreSQL database.

You can install and run RisingWave using Docker. Ensure that you have [Docker Desktop](https://docs.docker.com/get-docker/) installed and running first. 

First, clone the [risingwave](https://github.com/risingwavelabs/risingwave) repository.

```terminal
git clone https://github.com/risingwavelabs/risingwave.git
```

Open the repository in a terminal and navigate to the docker directory by using the following command.

```terminal
cd docker
```

Run the following code to start a RisingWave cluster.

```terminal
docker compose up -d
```

In a new command line window, run the following code to connect to RisingWave.

```terminal
psql -h localhost -p 4566 -d dev -U root
```

You can now start writing SQL queries to process streaming data. 

If you would like to explore other ways of installing RisingWave, see the [Quick start](https://docs.risingwave.com/docs/current/get-started/) guide.

For more information on deploying RisingWave with Docker Compose, see [Start RisingWave using Docker Compose](https://docs.risingwave.com/docs/current/risingwave-docker-compose/#connect-to-risingwave).




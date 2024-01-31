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

You can install and run RisingWave using Docker. Ensure that you have [Docker Desktop](https://docs.docker.com/get-docker/) installed and running first. If you would like to explore other ways of installing RisingWave, see the [Quick start](https://docs.risingwave.com/docs/current/get-started/) guide.

Run the following line of code to start RisingWave.

```terminal
docker run -it --pull=always -p 4566:4566 -p 5691:5691 risingwavelabs/risingwave:latest playground
```

In a new command line window, run the following line of code to connect to RisingWave.

```terminal
psql -h localhost -p 4566 -d dev -U root
```

You can now start writing SQL queries to process streaming data. 


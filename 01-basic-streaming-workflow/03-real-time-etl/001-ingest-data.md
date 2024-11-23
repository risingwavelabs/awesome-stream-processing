# Query and join data from Kafka and PostgreSQL

This demos shows how to ingest data from a Kafka topic and a PostgreSQL table. We will run a Python data generator that sends data to a Kafka topic.

## Prerequisites

To execute this demo, the following systems must be installed:

- A RisingWave instance

- A Kafka instance

- A PostgreSQL database

## Set up a Kafka message producer

### Start a Kafka instance

Refer to [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md#install-kafka) on how to install and start Kafka.

### Configure the data generator

For this demo, we have created a [Python data generator](/03-real-time-etl/data-generator.py) that will continously send messages to a Kafka topic. This generator is dependent on the `kafka` library.

Download the Python data generator file. Run the Python script.

## Set up a PostgreSQL database

Refer to [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md#install-postgresql) on how to install and configure your PostgreSQL database.

Next, create a table in PostgreSQL. We will create this table under the default database, `postgres`, and the default schema, `public`.

```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR,
    last_name VARCHAR,
    age INT
);
```

Insert some data into the table.

```sql
INSERT INTO users (first_name, last_name, age) VALUES
    ('John', 'Smith', 28),
    ('Emma', 'Johnson', 34),
    ('Michael', 'Brown', 41),
    ('Sophia', 'Williams', 25),
    ('David', 'Garcia', 37),
    ('Olivia', 'Jones', 29),
    ('William', 'Miller', 45),
    ('Ava', 'Martinez', 32),
    ('James', 'Davis', 39),
    ('Mia', 'Taylor', 27);
```

## Create a source in RisingWave

Refer to [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) on how to install and connect to RisingWave.

### Ingest data from a Kafka topic

To connect to the Kafka topic, use the following SQL query. We use the `CREATE SOURCE` command here, but `CREATE TABLE` can be used as well if we want to persist the data in RisingWave. Here we create a source named `site_visits`, which connects to the Kafka topic `website_visits`. A schema is also defined.

```sql
CREATE SOURCE site_visits (
    page_id INTEGER,
    user_id INTEGER, 
    action VARCHAR,
    action_time TIMESTAMPTZ
) WITH (
    connector = 'kafka',
    topic = 'website_visits',
    properties.bootstrap.server = 'localhost:9092'
) FORMAT PLAIN ENCODE JSON;
```

To learn more about the `CREATE SOURCE` command, see [`CREATE SOURCE`](https://docs.risingwave.com/docs/current/sql-create-source/) from the offical RisingWave documentation.

To learn more about the `CREATE TABLE` command, see [`CREATE TABLE`](https://docs.risingwave.com/docs/current/sql-create-table/) from the offical RisingWave documentation.

To learn more about how to consume data from Kafka, see [Ingest data from Kafka](https://docs.risingwave.com/docs/current/ingest-from-kafka/) from the official documentation.

### Ingest CDC data from PostgreSQL

Next, we will connect to the `users` table in PostgreSQL by using the following SQL query to ingest CDC data from PostgreSQL. With RisingWave you, can connect to multiple sources that reads data from different upstream systems. 

We create a `users` table in RisingWave that reads data from the PostgreSQL table by using the `CREATE TABLE` command. When ingesting CDC data, the `CREATE TABLE` command must be used instead of the `CREATE SOURCE` command to persist the data in RisingWave. Fill out the parameters accordingly based on your PostgreSQL database configurations.

```sql
CREATE TABLE users (
    id INTEGER primary key,
    first_name VARCHAR,
    last_name VARCHAR,
    age INTEGER
) WITH (
    connector = 'postgres-cdc',
    hostname = 'localhost',
    port = '5432',
    username = 'USERNAME',
    password = 'PASSWORD',
    database.name = 'postgres',
    schema.name = 'public',
    table.name = 'users'
);
```

To learn more about how to read data from PostgreSQL, see [Ingest data from PostgreSQL CDC](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/) from the official documentation.
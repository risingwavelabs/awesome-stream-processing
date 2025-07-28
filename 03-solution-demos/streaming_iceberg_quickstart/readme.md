# Build Your First **Streaming Iceberg Table** in 3 Simple Steps with RisingWave

Create tables that write directly to Apache Iceberg, stream data in real time, and keep everything query‑ready for Spark, Trino, or any other engine.

Enable **hosted_catalog** in RisingWave to create an Iceberg catalog without requiring external services.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash

git clone https://github.com/risingwavelabs/awesome-stream-processing.git

cd awesome-stream-processing/03-solution-demos/streaming_iceberg_quickstart

# Launch demo stack
docker compose up -d
```

The compose file starts a standalone RisingWave on localhost:4566 and a MinIO object store on localhost:9000, so you can follow the next steps exactly as written.

## 1. Create a connection with the hosted catalog

Connect to your RisingWave instance:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Tell RisingWave where to store table files and let it handle the metadata:

```sql
CREATE CONNECTION my_iceberg_connection
WITH (
    type                 = 'iceberg',
    warehouse.path       = 's3://icebergdata/demo',
    s3.access.key        = 'hummockadmin',
    s3.secret.key        = 'hummockadmin',
    s3.region            = 'us-east-1',
    s3.endpoint          = 'http://minio-0:9301',
    s3.path.style.access = 'true',
    hosted_catalog       = 'true'            -- 👈 one flag, no extra services!
);

SET iceberg_engine_connection = 'public.my_iceberg_connection';
```

> What happened?
> 
> 
> RisingWave just spun up a fully spec‑compliant Iceberg catalog inside its own metadata store, no Glue, Nessie, or external Postgres required.
> 

## 2. Create an Iceberg table

Activate the connection for your session and add `ENGINE = iceberg`:

```sql
-- Use the connection
SET iceberg_engine_connection = 'public.my_iceberg_connection';

-- Define the streaming table
CREATE TABLE machine_sensors (
  sensor_id   INT PRIMARY KEY,
  temperature DOUBLE,
  reading_ts  TIMESTAMP
)
WITH (commit_checkpoint_interval = 1)  -- low‑latency commits
ENGINE = iceberg;
```

The table is ready to accept streaming inserts and incremental merges.

## 3. Stream data in and query it

Insert this data into the Iceberg table:

```sql
INSERT INTO machine_sensors
VALUES
  (101, 25.5, NOW()),
  (102, 70.2, NOW());
```

Verify the commit:

```sql
SELECT * FROM machine_sensors;

 sensor_id | temperature |        reading_ts
-------------+-------------+---------------------------
       101 |        25.5 | 2025‑07‑17 15:04:56.123…
       102 |        70.2 | 2025‑07‑17 15:04:56.456…
```

Because the table resides in an open Iceberg format, you can immediately query it from Spark, Trino, Dremio, or DuckDB by pointing them at the same warehouse path and hosted catalog endpoint.

## Clean up

```bash
docker-compose down -v
```

## Recap

- **Provision** an Iceberg catalog: set `hosted_catalog = true`.
- **Create** streaming tables that write in Iceberg format straight to S3, GCS, Azure, or MinIO.
- **Query** the data from RisingWave or any Iceberg‑aware engine—no lock‑in, no extra services.

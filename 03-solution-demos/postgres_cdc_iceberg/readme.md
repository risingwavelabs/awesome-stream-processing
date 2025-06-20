# Real-Time PostgreSQL → Apache Iceberg CDC

Stream change-data-capture (CDC) events from PostgreSQL into Apache Iceberg using RisingWave’s native PostgreSQL CDC source and Iceberg sink. Query the continuously updated Iceberg lakehouse table with Spark, Trino, or Dremio, and ingest the results back into RisingWave using its source connector.

## Real-world use cases

This architecture is applicable across several industries for real-time and historical analytics:

| Industry | Application |
| --- | --- |
| E-commerce | Real-time order tracking, reporting, & analysis |
| FinTech | Transaction auditing |
| Healthcare | Patient record changes |
| SaaS | Billing and usage updates |

## **Prerequisites**

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## 1. Launch the demo cluster

### Clone the repo

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
```

### Start the stack

```bash
cd awesome-stream-processing/03-solution-demos/postgres_cdc_iceberg
docker compose up -d
```

The Compose file launches:

- **RisingWave** (single-node) on **localhost:4566**
- **PostgreSQL** (CDC-enabled) on **localhost:5432**
- **Iceberg REST catalog** + **MinIO** object store
- **Spark-Iceberg** client image

| Service | Container port | Localhost |
| --- | --- | --- |
| RisingWave | 4566 | 4566 |
| PostgreSQL | 5432 | 5432 |
| Iceberg REST API | 8181 | 8181 |
| MinIO API | 9000 | 9000 |

## 2. Prepare PostgreSQL

```bash
docker exec -it postgres psql -U myuser -d mydb
```

### What the Compose stack sets up

`postgres_prepare` (from `docker-compose.yml`) runs `postgres_prepare.sql` once at start-up to:

- Create `public.person` (PK `id`).
- Enable **REPLICA IDENTITY FULL** for full-row UPDATE/DELETE.
- Add the `rw_publication` publication.
- Insert 100 demo rows.

PostgreSQL is now ready for RisingWave replication.

Verify:

```sql
SELECT * FROM person LIMIT 5;
```

## 3. Create the CDC source table in RisingWave

```bash
psql -h localhost -p 4566 -d dev -U root
```

Define a source table that mirrors `public.person`:

```sql
CREATE TABLE person (
  id            INT PRIMARY KEY,
  name          VARCHAR,
  email_address VARCHAR,
  credit_card   VARCHAR,
  city          VARCHAR
) WITH (
  connector     = 'postgres-cdc',
  hostname      = 'postgres',
  port          = '5432',
  username      = 'myuser',
  password      = '123456',
  database.name = 'mydb',
  schema.name   = 'public',
  table.name    = 'person',              -- Postgres table
  slot.name     = 'person'               -- replication slot name
);

```

Quick check:

```sql
SELECT * FROM person LIMIT 5;
```

Sink CDC data to Iceberg (REST catalog + MinIO)

```sql
CREATE SINK person_iceberg_sink
FROM person
WITH (
    -- Iceberg sink
    connector              = 'iceberg',
    type                   = 'append-only',
    force_append_only      = 'true',          -- ← required

    -- REST catalog
    catalog.type           = 'rest',
    catalog.uri            = 'http://rest:8181',

    -- Warehouse location (MinIO bucket)
    warehouse.path         = 's3://warehouse',

    -- MinIO / S3 settings
    s3.endpoint            = 'http://minio:9000',
    s3.region              = 'us-east-1',
    s3.access.key          = 'admin',
    s3.secret.key          = 'password',
    s3.path.style.access   = 'true',

    -- Target namespace + table
    database.name          = 'default',
    table.name             = 'person',
    create_table_if_not_exists = true          -- Optional
);
```

## 4. Query Iceberg with SparkSQL

```bash
sudo docker exec -it spark-iceberg spark-sql \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.rest=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.rest.catalog-impl=org.apache.iceberg.rest.RESTCatalog \
  --conf spark.sql.catalog.rest.uri=http://rest:8181 \
  --conf spark.sql.catalog.rest.warehouse=s3://warehouse \
  --conf spark.sql.catalog.rest.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.rest.s3.endpoint=http://minio:9000 \
  --conf spark.sql.catalog.rest.s3.access-key=admin \
  --conf spark.sql.catalog.rest.s3.secret-key=password \
  --conf spark.sql.catalog.rest.s3.path-style-access=true
```

Preview CDC data inside Spark:

```sql
spark-sql ()> SELECT * FROM rest.default.person LIMIT 5;
```

Create a demo Iceberg table (`employees`) and populate it:

```sql
spark-sql ()> CREATE TABLE rest.default.employees (
  id       INT,
  name     STRING,
  dept     STRING,
  salary   DOUBLE
);

INSERT INTO rest.default.employees VALUES
  (1, 'Alice',  'Engineering', 95000.0),
  (2, 'Bob',    'Marketing',   64000.0),
  (3, 'Carlos', 'Engineering', 88000.0),
  (4, 'Dina',   'HR',          70000.0);
  
spark-sql ()> SELECT * FROM rest.default.employees;
```

## 5. Bring Iceberg data back into RisingWave

```sql
CREATE SOURCE employees_iceberg_source
WITH (
    -- Mandatory connector & catalog settings
    connector            = 'iceberg',
    catalog.type         = 'rest',
    catalog.uri          = 'http://rest:8181',

    -- Warehouse location (identical to the sink)
    warehouse.path       = 's3://warehouse',

    -- Object-store credentials (MinIO / S3)
    s3.endpoint          = 'http://minio:9000',
    s3.region            = 'us-east-1',
    s3.access.key        = 'admin',
    s3.secret.key        = 'password',
    s3.path.style.access = 'true',

    -- Target Iceberg identifier
    database.name        = 'default',
    table.name           = 'employees'
);

SELECT * FROM employees_iceberg_source;

```

## **6. Clean up**

```bash

docker compose-down -v
```

## Recap

- **Capture** logical replication from PostgreSQL into RisingWave.
- **Stream** CDC data into an Apache Iceberg table via RisingWave.
- **Query** low-latency, open-format analytics using Spark, Trino, or Dremio.
- **Ingest** results back into RisingWave from the Iceberg table using RisingWave's source connector.

# RisingWave → Lakekeeper → Iceberg → DuckDB

Create a streaming lakehouse with **Lakekeeper** and **MinIO**, stream upserts from **RisingWave** into **Apache Iceberg**, and query the same tables from **DuckDB**, no Glue or Nessie required.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

**Demo directory name:** `risingwave_lakekeeper_iceberg_duckdb`

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/risingwave_lakekeeper_iceberg_duckdb

# Launch demo stack
docker compose up -d
````

The compose file starts Lakekeeper at **127.0.0.1:8181**, RisingWave at **127.0.0.1:4566**, and MinIO (S3-compatible) at **127.0.0.1:9301**, matching the commands used below.

## 1. Provision a Lakekeeper warehouse (MinIO backend)

```bash
curl -X POST http://127.0.0.1:8181/management/v1/warehouse \
  -H 'content-type: application/json' \
  -d '{
    "warehouse-name": "minio_iceberg",
    "delete-profile": { "type": "hard" },
    "storage-credential": {
      "type": "s3",
      "credential-type": "access-key",
      "aws-access-key-id": "hummockadmin",
      "aws-secret-access-key": "hummockadmin"
    },
    "storage-profile": {
      "type": "s3",
      "bucket": "icebergdata",
      "region": "us-east-1",
      "flavor": "s3-compat",
      "endpoint": "http://127.0.0.1:9301",
      "path-style-access": true,
      "sts-enabled": false,
      "key-prefix": "warehouse1"
    }
  }'
```

## 2. Connect RisingWave and stream to Iceberg

Connect to RisingWave:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create an Iceberg **REST catalog** connection that points at the Lakekeeper catalog and MinIO:

```sql
CREATE CONNECTION my_connection
WITH (
  type = 'iceberg',
  catalog.type = 'rest',
  catalog.uri = 'http://127.0.0.1:8181/catalog',
  warehouse.path = 'minio_iceberg',
  s3.endpoint = 'http://127.0.0.1:9301',
  s3.region = 'us-east-1',
  s3.access.key = 'hummockadmin',
  s3.secret.key = 'hummockadmin',
  s3.path.style.access = 'true'
);
```

Create a table for a simple customer directory:

```sql
CREATE TABLE customer_profile (
  customer_id INT PRIMARY KEY,
  full_name   VARCHAR,
  email       VARCHAR,
  phone       VARCHAR,
  status      VARCHAR,
  city        VARCHAR,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ
);
```

Seed some rows:

```sql
INSERT INTO customer_profile (
  customer_id, full_name, email, phone, status, city, created_at, updated_at)
VALUES
  (1, 'Alex Johnson', 'alex.johnson@example.com', '+1-212-555-0101', 'active', 'New York','2025-08-15 09:12:00-04','2025-08-18 14:30:00-04'),
  (2, 'Maria Garcia', 'maria.garcia@example.com', '+1-415-555-0102', 'active', 'San Francisco','2025-08-16 08:05:00-07','2025-08-19 10:45:00-07'),
  (3, 'Ethan Brown',  'ethan.brown@example.com',  '+1-312-555-0103', 'suspended','Chicago','2025-08-17 11:10:00-05','2025-08-17 11:10:00-05');
```

Quick check:

```sql
SELECT * FROM customer_profile;
```

Define an Iceberg sink targeting Lakekeeper:

```sql
CREATE SINK customer_profile_sink FROM customer_profile
WITH (
  connector = 'iceberg',
  type = 'upsert',
  primary_key = 'customer_id',
  connection = my_connection,
  database.name = 'public',
  table.name = 'customer_profile',
  commit_checkpoint_interval = 3,
  create_table_if_not_exists = true
);
```

## 3. Query the Iceberg table from DuckDB

Install the DuckDB CLI:

```bash
curl https://install.duckdb.org | sh
```

Launch DuckDB:

```bash
~/.duckdb/cli/latest/duckdb
```

Install the needed extensions:

```sql
INSTALL aws;
INSTALL httpfs;
INSTALL iceberg;
```

Configure settings for MinIO (S3-compatible):

```sql
SET s3_region = 'us-east-1';
SET s3_endpoint = 'http://127.0.0.1:9301';
SET s3_access_key_id = 'hummockadmin';
SET s3_secret_access_key = 'hummockadmin';
SET s3_url_style = 'path';
SET s3_use_ssl = false;
```

Attach the Lakekeeper REST catalog and query the table:

```sql
ATTACH 'minio_iceberg' AS lakekeeper_catalog (
  TYPE ICEBERG,
  ENDPOINT 'http://127.0.0.1:8181/catalog',
  authorization_type 'none'
);

SELECT * FROM lakekeeper_catalog.public.customer_profile;
```

## Optional: Clean up (Docker)

> ⚠️ Only run this after you’ve fully tested.
>
> * `-v` deletes Docker volumes (all persisted data), in addition to stopping and removing containers and networks.

**If you want a full cleanup (including volumes/data):**

```bash
docker compose down -v
```

## Recap

* **Provision** a Lakekeeper warehouse backed by MinIO.
* **Stream** upserts from RisingWave to Iceberg via a Lakekeeper REST catalog.
* **Query** the same tables from DuckDB using the catalog—no copies, same data.

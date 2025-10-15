# RisingWave → Lakekeeper → Iceberg → DuckDB
RisingWave lets you create Apache Iceberg–native tables via its REST-based catalog with **Lakekeeper**. You can stream data from these **RisingWave** tables into **Apache Iceberg**, then query the same tables from DuckDB, no Glue or Nessie required.

## Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.
## Clone the demo repo and start the stack

**Demo directory:** `risingwave_lakekeeper_iceberg_duckdb`

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/risingwave_lakekeeper_iceberg_duckdb

# Launch demo stack
docker compose up -d
```

The **Compose** file starts:

* **Lakekeeper** at `127.0.0.1:8181` and provisions the Lakekeeper warehouse
* **RisingWave** at `127.0.0.1:4566`
* **MinIO (S3-compatible)** at `127.0.0.1:9301`

## Connect RisingWave and stream to Iceberg

Connect to RisingWave:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create an Iceberg **REST catalog** connection pointing to Lakekeeper and MinIO:

```sql
CREATE CONNECTION lakekeeper_catalog_conn
WITH (
    type = 'iceberg',
    catalog.type = 'rest',
    catalog.uri = 'http://lakekeeper:8181/catalog/',
    warehouse.path = 'risingwave-warehouse',
    s3.access.key = 'hummockadmin',
    s3.secret.key = 'hummockadmin',
    s3.path.style.access = 'true',
    s3.endpoint = 'http://minio-0:9301',
    s3.region = 'us-east-1'
);
```

Set it as the default Iceberg connection:

```sql
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';
```

Create a simple customer directory table:

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
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;
```

Seed a few rows:

```sql
INSERT INTO customer_profile (
  customer_id, full_name, email, phone, status, city, created_at, updated_at)
VALUES
  (1, 'Alex Johnson', 'alex.johnson@example.com', '+1-212-555-0101', 'active', 'New York','2025-08-15 09:12:00-04','2025-08-18 14:30:00-04'),
  (2, 'Maria Garcia', 'maria.garcia@example.com', '+1-415-555-0102', 'active', 'San Francisco','2025-08-16 08:05:00-07','2025-08-19 10:45:00-07'),
  (3, 'Ethan Brown',  'ethan.brown@example.com',  '+1-312-555-0103', 'suspended','Chicago','2025-08-17 11:10:00-05','2025-08-17 11:10:00-05');
```

Verify:

```sql
SELECT * FROM customer_profile;
```

## Query the Iceberg table from DuckDB

Install the DuckDB CLI:

```bash
curl https://install.duckdb.org | sh
```

Map `minio-0` to `127.0.0.1` on the host so DuckDB (outside Compose) can reach MinIO at `http://minio-0:9301`:

```bash
echo "127.0.0.1 minio-0" | sudo tee -a /etc/hosts
```

Launch DuckDB:

```bash
~/.duckdb/cli/latest/duckdb
```

Install the required extensions:

```sql
INSTALL aws;
INSTALL httpfs;
INSTALL iceberg;
```

Configure MinIO (S3-compatible) settings:

```sql
SET s3_region = 'us-east-1';
SET s3_endpoint = 'http://minio-0:9301';
SET s3_access_key_id = 'hummockadmin';
SET s3_secret_access_key = 'hummockadmin';
SET s3_url_style = 'path';
SET s3_use_ssl = false;
```

Attach the Lakekeeper REST catalog and query the table:

```sql
ATTACH 'risingwave-warehouse' AS lakekeeper_catalog (
  TYPE ICEBERG,
  ENDPOINT 'http://127.0.0.1:8181/catalog/',
  AUTHORIZATION_TYPE 'none'
);

SELECT * FROM lakekeeper_catalog.public.customer_profile;
```
## Optional: Clean up (Docker)

> **⚠️ Only run this after you’ve fully tested.**
> `-v` deletes Docker **volumes** (all persisted data) in addition to stopping and removing containers and networks.

Full cleanup (including volumes/data):

```bash
docker compose down -v
```
## Recap
* **Provision** a Lakekeeper warehouse backed by MinIO.
* **Stream** data from RisingWave to Iceberg via a Lakekeeper REST catalog.
* **Query** the same tables from DuckDB using that catalog, no copies, it’s the same data.

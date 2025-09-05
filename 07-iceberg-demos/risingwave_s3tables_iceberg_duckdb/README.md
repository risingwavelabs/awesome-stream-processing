# RisingWave + Amazon S3 Tables + DuckDB

RisingWave integrates with **Amazon S3 Tables** to bring **Apache Iceberg** into your streaming pipelines: ingest from S3 Tables, sink results back, manage tables via the S3 Tables catalog, and query them with **DuckDB**. This AWS-native flow simplifies architecture, improves interoperability, and lets you focus on building robust, scalable streaming applications.

## Prerequisites

- An AWS account with **S3 Tables** enabled in the target region.
- [Docker](https://docs.docker.com/get-docker/) (to run RisingWave via a single container).
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/) to connect to RisingWave.

## Clone the demo repo and start the stack

**Demo directory name:** `risingwave_s3tables_iceberg_duckdb`

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/risingwave_s3tables_iceberg_duckdb
````

No local catalog or MinIO containers are required for this S3 Tables variant (you’ll only run RisingWave).

## 1. Prepare the Iceberg catalog on AWS S3 Tables

Make sure your S3 Tables bucket exists and note its ARN and region.

<img width="960" height="427" alt="S3 Table created" src="https://github.com/user-attachments/assets/c1100c33-b4f7-4056-8b9a-ae93a1b302f1" />

Example bucket ARN used below:

```
arn:aws:s3tables:us-east-1:023334545:bucket/fahad-s3-table-bucket
```

## 2. Connect RisingWave and stream to Iceberg

Run RisingWave:

```bash
docker run -it --pull=always -p 4566:4566 -p 5691:5691 risingwavelabs/risingwave:latest single_node
```

Connect to RisingWave:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create the Iceberg REST catalog connection pointing to AWS S3 Tables:

```sql
CREATE CONNECTION my_s3_tables_conn WITH (
    type = 'iceberg',
    warehouse.path = 'arn:aws:s3tables:us-east-1:023334545:bucket/fahad-s3-table-bucket',
    catalog.type = 'rest',
    catalog.uri = 'https://s3tables.us-east-1.amazonaws.com/iceberg',
    catalog.rest.signing_region = 'us-east-1',
    catalog.rest.sigv4_enabled = true,
    catalog.rest.signing_name = 's3tables',
    s3.access.key = 'YOUR_ACCESS_KEY_ID',
    s3.secret.key = 'YOUR_SECRET_ACCESS_KEY',
    s3.region = 'us-east-1'
);
```

Create a banking accounts table (RisingWave):

```sql
CREATE TABLE bank_accounts (
  account_id      BIGINT PRIMARY KEY,
  customer_id     BIGINT,
  account_type    VARCHAR,
  currency        VARCHAR,
  balance         DECIMAL,
  account_status  VARCHAR,
  branch_code     VARCHAR,
  created_at      TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ
);
```

Seed sample data:

```sql
INSERT INTO bank_accounts (
  account_id, customer_id, account_type, currency, balance, account_status, branch_code, created_at, updated_at
) VALUES
  (1001, 501, 'CHECKING', 'USD',   4250.75,  'active',     'NYC01', '2025-08-15 09:12:00-04', '2025-08-18 14:30:00-04'),
  (1002, 502, 'SAVINGS',  'USD',  15000.00,  'active',     'SFO02', '2025-08-16 08:05:00-07', '2025-08-19 10:45:00-07'),
  (1003, 503, 'LOAN',     'USD', -20000.00,  'delinquent', 'CHI03', '2025-08-17 11:10:00-05', '2025-08-17 11:10:00-05'),
  (1004, 504, 'SAVINGS',  'USD',    980.00,  'frozen',     'DAL04', '2025-08-18 12:00:00-05', '2025-08-20 09:00:00-05');
```

Create the Iceberg sink to AWS S3 Tables:

```sql
CREATE SINK bank_accounts_sink FROM bank_accounts
WITH (
  connector = 'iceberg',
  type = 'upsert',
  primary_key = 'account_id',
  connection = my_s3_tables_conn,
  database.name = 'public',
  table.name = 'bank_accounts',
  commit_checkpoint_interval = 3,
  create_table_if_not_exists = true
);
```

## 3. Query the Iceberg table from DuckDB

Install DuckDB CLI:

```bash
curl https://install.duckdb.org | sh
```

Launch DuckDB:

```bash
~/.duckdb/cli/latest/duckdb
```

Install extensions and attach the S3 Tables catalog:

```sql
INSTALL aws;
INSTALL httpfs;
INSTALL iceberg;

CREATE SECRET (
  TYPE s3,
  KEY_ID 'YOUR_ACCESS_KEY_ID',
  SECRET 'YOUR_SECRET_ACCESS_KEY',
  REGION 'us-east-1'
);

ATTACH 'arn:aws:s3tables:us-east-1:023334545:bucket/fahad-s3-table-bucket' AS s3_tables (
  TYPE ICEBERG,
  ENDPOINT_TYPE S3_TABLES
);

SELECT * FROM s3_tables.public.bank_accounts;
```

## Optional: Clean up (Docker)

> ⚠️ Only run this after you’ve fully tested.
>
> * If you started RisingWave with `docker run`, stop the container (Ctrl-C if running in the foreground, or `docker ps` + `docker stop <id>`).

## Recap

* **Use** Amazon S3 Tables as the Iceberg REST catalog (no Glue or Nessie).
* **Stream** upserts from RisingWave into Iceberg on S3 Tables using the RisingWave sink.
* **Query** the same tables with **DuckDB** directly via the S3 Tables catalog.

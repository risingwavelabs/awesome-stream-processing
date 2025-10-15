# PostgreSQL CDC → Iceberg (via RisingWave) → Query with Spark
Stream change-data-capture (CDC) events from PostgreSQL into **Apache Iceberg** using **RisingWave’s** native `postgres-cdc` source and Iceberg Table Engine. Then query the continuously updated Iceberg table with **Spark SQL**.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/postgres_to_rw_iceberg_spark

# Launch demo stack
docker compose up -d
````
The **Compose** file starts **Lakekeeper** at `127.0.0.1:8181` and provisions the Lakekeeper warehouse, starts **RisingWave** at `127.0.0.1:4566`, and starts a **MinIO** object store at `127.0.0.1:9000`, so you can follow the next steps exactly as written.

## 1. Prepare PostgreSQL (seed data + CDC changes)

Connect to the Postgres container:

```bash
docker exec -it postgres psql -U myuser -d mydb
```

Create the table named `card_transactions`:

```sql
CREATE TABLE public.card_transactions (
  transaction_id   BIGINT PRIMARY KEY,
  account_id       BIGINT,
  card_last4       VARCHAR,
  txn_ts           TIMESTAMPTZ,
  amount           NUMERIC,
  currency         VARCHAR,
  direction        VARCHAR,
  merchant_name    VARCHAR,
  merchant_mcc     VARCHAR,
  channel          VARCHAR,
  city             VARCHAR,
  country          VARCHAR,
  tran_status      VARCHAR,
  is_fraud_suspect BOOLEAN,
  created_at       TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ
);
```

Seed a few rows into the table:

```sql
INSERT INTO public.card_transactions (
  transaction_id, account_id, card_last4, txn_ts, amount, currency, direction,
  merchant_name, merchant_mcc, channel, city, country, tran_status
) VALUES
  (202508260001, 1001001, '1234', now() - interval '1 hour',  84.23,  'USD','debit','Whole Foods Market','5411','POS','Seattle','US','pending'),
  (202508260002, 1001001, '1234', now() - interval '40 min',   52.10, 'USD','debit','Shell Gas Station','5541','POS','San Jose','US','posted'),
  (202508260003, 1002002, '7788', now() - interval '20 min', 1299.99, 'USD','debit','Best Buy','5732','ECOM','Austin','US','pending'),
  (202508260004, 1003003, '9900', now() - interval '10 min',   35.00, 'USD','credit','Wallet Refund','5645','ECOM','Boston','US','posted');
```

Simulate CDC (updates + a new insert):

```sql
-- pending -> posted
UPDATE public.card_transactions
SET tran_status='posted', updated_at=now()
WHERE tran_status='pending' AND merchant_name='Whole Foods Market';

-- reversal + fraud flag
UPDATE public.card_transactions
SET tran_status='reversed', updated_at=now(), is_fraud_suspect=true
WHERE merchant_name='Best Buy' AND tran_status='pending';

-- new declined swipe (new numeric ID)
INSERT INTO public.card_transactions (
  transaction_id, account_id, card_last4, txn_ts, amount, currency, direction,
  merchant_name, merchant_mcc, channel, city, country, tran_status
) VALUES (
  202508260005, 1002002, '7788', now(), 42.00, 'USD','debit',
  'QuickMart','5411','POS','New York','US','declined'
);
```

Sanity check:

```sql
SELECT * FROM card_transactions ORDER BY transaction_id LIMIT 5;
```

## 2. Create the CDC source table and Iceberg sink in RisingWave

Connect to RisingWave with `psql`:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create a streaming CDC source table in RisingWave that mirrors Postgres:

```sql
CREATE TABLE card_transactions_src (
  transaction_id   BIGINT PRIMARY KEY,
  account_id       BIGINT,
  card_last4       VARCHAR,
  txn_ts           TIMESTAMPTZ,
  amount           NUMERIC,
  currency         VARCHAR,
  direction        VARCHAR,
  merchant_name    VARCHAR,
  merchant_mcc     VARCHAR,
  channel          VARCHAR,
  city             VARCHAR,
  country          VARCHAR,
  tran_status      VARCHAR,
  is_fraud_suspect BOOLEAN,
  created_at       TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ
) WITH (
  connector     = 'postgres-cdc',
  hostname      = 'postgres',
  port          = '5432',
  username      = 'myuser',
  password      = '123456',
  database.name = 'mydb',
  schema.name   = 'public',
  table.name    = 'card_transactions',
  slot.name     = 'card_transactions'
);
```

Quick check:

```sql
SELECT * FROM card_transactions_src LIMIT 5;
```

Tell RisingWave where to store table files and let it handle the metadata:

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

> What happened?
>
> RisingWave just spun up a fully spec-compliant Iceberg catalog, no Glue, Nessie, or external Postgres required.

Activate the connection for your session and add `ENGINE = iceberg`:

```sql
-- Use the connection
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn;

-- Create the Iceberg table fed by the CDC source
CREATE TABLE card_transactions_src_iceberg (
  transaction_id   BIGINT PRIMARY KEY,
  account_id       BIGINT,
  card_last4       VARCHAR,
  txn_ts           TIMESTAMPTZ,
  amount           NUMERIC,
  currency         VARCHAR,
  direction        VARCHAR,
  merchant_name    VARCHAR,
  merchant_mcc     VARCHAR,
  channel          VARCHAR,
  city             VARCHAR,
  country          VARCHAR,
  tran_status      VARCHAR,
  is_fraud_suspect BOOLEAN,
  created_at       TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ
)
WITH (commit_checkpoint_interval = 1)  -- low-latency commits
ENGINE = iceberg;

INSERT INTO card_transactions_src_iceberg
SELECT * FROM card_transactions_src;

-- Validate it is receiving rows
SELECT * FROM card_transactions_src_iceberg LIMIT 5;
```

Because the table resides in an open Iceberg format, you can immediately query it from Spark, Trino, or Dremio by pointing them at the same warehouse path and hosted catalog endpoint.

## 3. Query the Iceberg table via Spark

### Install Apache Spark (if not installed)

### 1. Install Java (required)

Spark works with Java 8/11/17 (LTS). First check:

```bash
java -version
```

If it’s missing, install a JDK via your OS package manager (e.g., `apt`, `dnf`, `pacman`, or `brew`) and ensure `JAVA_HOME` is set.

If you're on Ubuntu and want to install Spark:

```bash
sudo apt update
sudo apt install openjdk-11-jdk -y
```

### 2. Download Spark

```bash
cd ~
curl -L -o spark-3.5.1-bin-hadoop3.tgz https://archive.apache.org/dist/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz
tar -xzf spark-3.5.1-bin-hadoop3.tgz
mv spark-3.5.1-bin-hadoop3 "$HOME/spark"
```

### 3. Add Spark to PATH

Add the following to your shell config (`~/.bashrc` or `~/.zshrc`):

```bash
export SPARK_HOME="$HOME/spark"
export PATH="$SPARK_HOME/bin:$PATH"
```

Reload your shell:

```bash
source ~/.bashrc   # or: source ~/.zshrc
```

### 4. Check if Spark is installed

```bash
spark-shell --version
```

You should see the Spark version printed.

### 5. Configure & run Spark SQL (Iceberg + MinIO + REST)

Map `minio-0` to `127.0.0.1` on the host so Spark (outside Compose) can reach MinIO at `http://minio-0:9301`:
```bash
echo "127.0.0.1 minio-0" | sudo tee -a /etc/hosts
```
Now, run this to connect with the Spark:
```bash
spark-sql \
  --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.2,org.apache.iceberg:iceberg-aws-bundle:1.9.2" \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.defaultCatalog=lakekeeper \
  --conf spark.sql.catalog.lakekeeper=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.lakekeeper.catalog-impl=org.apache.iceberg.rest.RESTCatalog \
  --conf spark.sql.catalog.lakekeeper.uri=http://127.0.0.1:8181/catalog/ \
  --conf spark.sql.catalog.lakekeeper.warehouse=risingwave-warehouse \
  --conf spark.sql.catalog.lakekeeper.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.lakekeeper.s3.endpoint=http://minio-0:9301 \
  --conf spark.sql.catalog.lakekeeper.s3.region=us-east-1 \
  --conf spark.sql.catalog.lakekeeper.s3.path-style-access=true \
  --conf spark.sql.catalog.lakekeeper.s3.access-key-id=hummockadmin \
  --conf spark.sql.catalog.lakekeeper.s3.secret-access-key=hummockadmin
```

Preview CDC data inside Spark:

```sql
SELECT * FROM public.card_transactions_src_iceberg LIMIT 5;
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

* **Capture**: Logical CDC from PostgreSQL into RisingWave.
* **Sink**: RisingWave streams rows into an **Iceberg** table stored on MinIO.
* **Query**: Use Spark SQL (RisingWave self-hosted catalog) to read the same table with open formats and fresh data.

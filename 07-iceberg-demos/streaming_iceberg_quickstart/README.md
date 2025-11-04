# Build Your First **Streaming Iceberg Table** in 3 Simple Steps with RisingWave
Create tables that write directly to Apache Iceberg, stream data in real time, and keep everything query-ready for Spark, Trino, or any other engine.
Use RisingWave with a self-hosted, REST-based Lakekeeper catalog to create an Iceberg catalog, requiring no external services.

<img width="2048" height="1056" alt="image" src="https://github.com/user-attachments/assets/be7eb6c4-f9f9-4d10-a483-9a420a61a00d" />

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/streaming_iceberg_quickstart

# Launch demo stack
docker compose up -d
````
The **Compose** file starts **Lakekeeper** at `127.0.0.1:8181` and provisions the Lakekeeper warehouse, starts **RisingWave** at `127.0.0.1:4566`, and starts a **MinIO** object store at `127.0.0.1:9000`, so you can follow the next steps exactly as written.

## 1. Create a connection with the self-hosted catalog

Connect to your RisingWave instance:

```bash
psql -h localhost -p 4566 -d dev -U root
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
> RisingWave has just spun up a fully spec-compliant Iceberg catalog within its own metadata store, eliminating the need for Glue, Nessie, or external Postgres.

## 2. Create an Iceberg table

Activate the connection for your session and add `ENGINE = iceberg`:

```sql
-- Use the connection
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';

-- Define the streaming table (crypto use case)
CREATE TABLE crypto_trades (
  trade_id  BIGINT PRIMARY KEY,
  symbol    VARCHAR,
  price     DOUBLE,
  quantity  DOUBLE,
  side      VARCHAR,     -- e.g., 'BUY' or 'SELL'
  exchange  VARCHAR,     -- e.g., 'binance', 'coinbase'
  trade_ts  TIMESTAMP
)
WITH (commit_checkpoint_interval = 1)  -- low-latency commits
ENGINE = iceberg;
```
The table is ready to accept streaming inserts and incremental merges.

### Stream data in and query it

Insert this data into the Iceberg table:

```sql
INSERT INTO crypto_trades
VALUES
  (1000001, 'BTCUSDT', 57321.25, 0.005, 'BUY', 'binance', NOW()),
  (1000002, 'ETHUSDT', 2578.10, 0.250, 'SELL', 'coinbase', NOW()),
  (1000003, 'SOLUSDT', 168.42, 5.75, 'BUY', 'binance', NOW()),
  (1000004, 'XRPUSDT', 0.546, 1200, 'SELL', 'coinbase', NOW()),
  (1000005, 'LTCUSDT', 72.15, 3.20, 'BUY', 'binance', NOW());

```
Verify the commit:

```sql
SELECT * FROM crypto_trades;
 trade_id | symbol  |  price   | quantity | side | exchange |        trade_ts
----------+---------+----------+----------+------+----------+----------------------------
  1000001 | BTCUSDT | 57321.25 |   0.005  | BUY  | binance  | 2025-07-17 15:04:56.123
  1000002 | ETHUSDT |  2578.10 |   0.250  | SELL | coinbase | 2025-07-17 15:04:56.456
  1000003 | SOLUSDT |   168.42 |   5.750  | BUY  | binance  | 2025-07-17 15:04:56.789
  1000004 | XRPUSDT |     0.546| 1200.000 | SELL | coinbase | 2025-07-17 15:04:57.012
  1000005 | LTCUSDT |    72.15 |   3.200  | BUY  | binance  | 2025-07-17 15:04:57.345
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
### 5. Configure & Run Spark SQL (Iceberg + MinIO + REST)
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
Then run a query:
```sql
select * from public.crypto_trades;
```

## Optional: Clean up (Docker)

> ⚠️ Only run this after you’ve fully tested.
>
> * `v` deletes Docker **volumes** (all persisted data), in addition to stopping and removing containers and networks.

**If you want a full cleanup (including volumes/data):**

```bash
docker compose down -v
```

## Recap

* **Provision** a REST-based Lakekeeper Iceberg catalog.
* **Create** streaming tables that write in Iceberg format straight to S3, GCS, Azure, or MinIO.
* **Query** the data from RisingWave or any Iceberg-aware engine (Spark), no lock-in, no extra services.

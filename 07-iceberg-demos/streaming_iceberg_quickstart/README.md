# Build Your First **Streaming Iceberg Table** in 3 Simple Steps with RisingWave

Create tables that write directly to Apache Iceberg, stream data in real time, and keep everything query-ready for Spark, Trino, or any other engine.
Enable **hosted_catalog** in RisingWave to create an Iceberg catalog without requiring external services.

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

The compose file starts a standalone RisingWave on localhost:4566 and a MinIO object store on localhost:9000, so you can follow the next steps exactly as written.

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
```

> What happened?
>
> RisingWave just spun up a fully spec-compliant Iceberg catalog inside its own metadata store, no Glue, Nessie, or external Postgres required.

## 2. Create an Iceberg table

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
WITH (commit_checkpoint_interval = 1)  -- low-latency commits
ENGINE = iceberg;
```

The table is ready to accept streaming inserts and incremental merges.

### Stream data in and query it

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
       101 |        25.5 | 2025-07-17 15:04:56.123…
       102 |        70.2 | 2025-07-17 15:04:56.456…
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

### 5. Configure & Run Spark SQL (Iceberg + MinIO + JDBC)

```bash
spark-sql \
  --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.2,org.apache.iceberg:iceberg-aws-bundle:1.9.2,org.postgresql:postgresql:42.7.4" \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.defaultCatalog=dev \
  --conf spark.sql.catalog.dev=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.dev.catalog-impl=org.apache.iceberg.jdbc.JdbcCatalog \
  --conf spark.sql.catalog.dev.uri=jdbc:postgresql://127.0.0.1:4566/dev \
  --conf spark.sql.catalog.dev.jdbc.user=postgres \
  --conf spark.sql.catalog.dev.jdbc.password=123 \
  --conf spark.sql.catalog.dev.warehouse=s3://hummock001/my_iceberg_connection \
  --conf spark.sql.catalog.dev.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.dev.s3.endpoint=http://127.0.0.1:9301 \
  --conf spark.sql.catalog.dev.s3.region=us-east-1 \
  --conf spark.sql.catalog.dev.s3.path-style-access=true \
  --conf spark.sql.catalog.dev.s3.access-key-id=hummockadmin \
  --conf spark.sql.catalog.dev.s3.secret-access-key=hummockadmin
```

Then run a query:

```sql
select * from dev.public.machine_sensors;
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

* **Provision** an Iceberg catalog: set `hosted_catalog = true`.
* **Create** streaming tables that write in Iceberg format straight to S3, GCS, Azure, or MinIO.
* **Query** the data from RisingWave or any Iceberg-aware engine (Spark), no lock-in, no extra services.

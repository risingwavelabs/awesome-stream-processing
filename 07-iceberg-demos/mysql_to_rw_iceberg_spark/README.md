# MySQL CDC → Iceberg (via RisingWave) → Query with Spark

Ingest MySQL change-data-capture (CDC) events using **RisingWave’s** `mysql-cdc` connector and write to **Apache Iceberg** via the Iceberg Table Engine. Then query the continuously updated table with **Spark SQL**.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/mysql_to_rw_iceberg_spark

# Launch demo stack
docker compose up -d
````

The compose file starts a standalone RisingWave on localhost:4566, a MySQL container, and a MinIO object store on localhost:9301, so you can follow the next steps exactly as written.

## 1. Prepare MySQL (seed data + CDC changes)

Connect to the MySQL container:

```bash
docker exec -it mysql mysql -uroot -p123456 mydb
```

Create the **ride-hailing trips** table and seed rows:

```sql
CREATE TABLE IF NOT EXISTS ride_hailing_trips (
  trip_id        BIGINT PRIMARY KEY,
  rider_id       BIGINT NOT NULL,
  driver_id      BIGINT,
  request_ts     DATETIME NOT NULL,
  pickup_ts      DATETIME NULL,
  dropoff_ts     DATETIME NULL,
  pickup_city    VARCHAR(64),
  pickup_zone    VARCHAR(64),
  dropoff_city   VARCHAR(64),
  dropoff_zone   VARCHAR(64),
  distance_km    DECIMAL(6,2),
  fare_amount    DECIMAL(10,2),
  currency       VARCHAR(3),
  trip_status    VARCHAR(16),
  is_surge       TINYINT(1) DEFAULT 0,
  created_at     DATETIME,
  updated_at     DATETIME
);

INSERT INTO ride_hailing_trips
  (trip_id, rider_id, driver_id, request_ts, pickup_ts, dropoff_ts,
   pickup_city, pickup_zone, dropoff_city, dropoff_zone, distance_km,
   fare_amount, currency, trip_status, is_surge, created_at, updated_at)
VALUES
  (202508260201, 7001001, 8002001, NOW() - INTERVAL 60 MINUTE, NULL, NULL,
   'Seattle','Capitol Hill','Seattle','South Lake Union', NULL,
   NULL,'USD','requested', 0, NOW(), NOW()),
  (202508260202, 7001001, 8002001, NOW() - INTERVAL 40 MINUTE, NOW() - INTERVAL 35 MINUTE, NULL,
   'San Jose','Downtown','San Jose','Willow Glen', 5.10,
   14.50,'USD','picked_up', 0, NOW(), NOW()),
  (202508260203, 7002002, 8003003, NOW() - INTERVAL 20 MINUTE, NULL, NULL,
   'Austin','Zilker','Austin','Domain', NULL,
   NULL,'USD','requested', 1, NOW(), NOW()),
  (202508260204, 7003003, 8004004, NOW() - INTERVAL 10 MINUTE, NOW() - INTERVAL 9 MINUTE, NOW() - INTERVAL 2 MINUTE,
   'Boston','Back Bay','Boston','Seaport', 6.80,
   22.00,'USD','complete', 0, NOW(), NOW());
```

Simulate CDC (updates + a new insert):

```sql
-- requested -> accepted -> picked_up (and set pickup_ts)
UPDATE ride_hailing_trips
SET trip_status='accepted', updated_at=NOW()
WHERE trip_id=202508260201 AND trip_status='requested';

UPDATE ride_hailing_trips
SET trip_status='picked_up', pickup_ts=NOW() - INTERVAL 5 MINUTE, updated_at=NOW()
WHERE trip_id=202508260201 AND trip_status='accepted';

-- requested -> canceled (surge stays 1)
UPDATE ride_hailing_trips
SET trip_status='canceled', updated_at=NOW()
WHERE trip_id=202508260203 AND trip_status='requested';

-- new in-progress trip
INSERT INTO ride_hailing_trips
  (trip_id, rider_id, driver_id, request_ts, pickup_ts, dropoff_ts,
   pickup_city, pickup_zone, dropoff_city, dropoff_zone, distance_km,
   fare_amount, currency, trip_status, is_surge, created_at, updated_at)
VALUES
  (202508260205, 7002002, 8003003, NOW(), NOW(), NULL,
   'New York','Chelsea','New York','Midtown', 2.00,
   9.75, 'USD','picked_up', 0, NOW(), NOW());

-- sanity check
SELECT * FROM ride_hailing_trips ORDER BY trip_id LIMIT 5;

-- Create CDC user with replication privileges and apply grants
CREATE USER IF NOT EXISTS 'mysqluser'@'%' IDENTIFIED BY 'mysqlpw';
GRANT SELECT, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'mysqluser'@'%';
FLUSH PRIVILEGES;
```

> MySQL `DATETIME` maps to `TIMESTAMP` in RisingWave, and MySQL `TIMESTAMP` maps to `TIMESTAMPTZ`.

## 2. Create the CDC source and table in RisingWave

Connect to RisingWave with `psql`:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create a **shared MySQL CDC source** (binlog reader). Then bind a **CDC table** from that source and include the upstream commit timestamp:

```sql
-- 1) Shared CDC source (point at your MySQL)
CREATE SOURCE mysql_mydb WITH (
  connector     = 'mysql-cdc',
  hostname      = 'mysql',
  port          = '3306',
  username      = 'root',
  password      = '123456',
  database.name = 'mydb',
  server.id     = 5888
);

-- 2) Bind a CDC table to the upstream table (PK required)
CREATE TABLE ride_hailing_trips_src (
  trip_id        BIGINT PRIMARY KEY,
  rider_id       BIGINT,
  driver_id      BIGINT,
  request_ts     TIMESTAMP,
  pickup_ts      TIMESTAMP,
  dropoff_ts     TIMESTAMP,
  pickup_city    VARCHAR,
  pickup_zone    VARCHAR,
  dropoff_city   VARCHAR,
  dropoff_zone   VARCHAR,
  distance_km    NUMERIC,
  fare_amount    NUMERIC,
  currency       VARCHAR,
  trip_status    VARCHAR,
  is_surge       BOOLEAN,
  created_at     TIMESTAMP,
  updated_at     TIMESTAMP
)
INCLUDE TIMESTAMP AS commit_ts
FROM mysql_mydb TABLE 'mydb.ride_hailing_trips';

-- quick peek
SELECT * FROM ride_hailing_trips_src LIMIT 5;
```

## 3. Create the Iceberg connection & table, and stream into it

Tell RisingWave where to store Iceberg files (MinIO/S3) and enable the Iceberg Table Engine. Then create a standard Iceberg table and **stream** from the CDC table:

```sql
-- Connection: RisingWave-managed (hosted) Iceberg catalog on S3/MinIO
CREATE CONNECTION my_iceberg_connection
WITH (
  type                 = 'iceberg',
  warehouse.path       = 's3://icebergdata/demo',
  s3.access.key        = 'hummockadmin',
  s3.secret.key        = 'hummockadmin',
  s3.region            = 'us-east-1',
  s3.endpoint          = 'http://minio-0:9301',
  s3.path.style.access = 'true',
  hosted_catalog       = 'true'
);

-- Use this connection for Iceberg engine tables
SET iceberg_engine_connection = 'public.my_iceberg_connection';

-- Create an Iceberg table (native RW-managed Iceberg)
CREATE TABLE ride_hailing_trips_iceberg (
  trip_id        BIGINT PRIMARY KEY,
  rider_id       BIGINT,
  driver_id      BIGINT,
  request_ts     TIMESTAMP,
  pickup_ts      TIMESTAMP,
  dropoff_ts     TIMESTAMP,
  pickup_city    VARCHAR,
  pickup_zone    VARCHAR,
  dropoff_city   VARCHAR,
  dropoff_zone   VARCHAR,
  distance_km    NUMERIC,
  fare_amount    NUMERIC,
  currency       VARCHAR,
  trip_status    VARCHAR,
  is_surge       BOOLEAN,
  created_at     TIMESTAMP,
  updated_at     TIMESTAMP,
  commit_ts      TIMESTAMP
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;

INSERT INTO ride_hailing_trips_iceberg
SELECT *
FROM ride_hailing_trips_src;

-- quick peek
SELECT * FROM ride_hailing_trips_iceberg ORDER BY trip_id LIMIT 5;
```

Iceberg tables created via the **Iceberg Table Engine** are standard Iceberg tables readable by Spark/Trino/Dremio.

## 4. Query the Iceberg table via Spark

### Install Apache Spark (if not installed)

### 1. Install Java (required)

```bash
java -version
```

If it’s missing, install a JDK via your OS package manager and ensure `JAVA_HOME` is set.

On Ubuntu:

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

### 5. Configure & run Spark SQL (Iceberg + MinIO + JDBC)

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

Query with SparkSQL:

```sql
SELECT * FROM dev.public.ride_hailing_trips_iceberg LIMIT 5;
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

* **Capture**: Direct MySQL CDC (binlog) into RisingWave via `mysql-cdc`.
* **Store**: Stream rows into an **Iceberg** table using the Iceberg Table Engine.
* **Query**: Point Spark SQL at the same Iceberg catalog + object store and run queries over fresh, open-format data.

# Streaming Join to Apache Iceberg with RisingWave

This demo showcases a multi-way streaming join in a logistics scenario (trucks, drivers, shipments, routes, warehouses, fuel, and maintenance) and writes the joined stream to an Apache Iceberg table. It creates a table that writes directly to Iceberg, streams data in real time, and keeps everything query-ready for Spark, Trino, or any other engine. Enable the `hosted_catalog` option in RisingWave to create an Iceberg catalog without external services.

## Prerequisites

* [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
* [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/logistics_multiway_streaming_join_iceberg

# Launch demo stack
docker compose up -d
```

## 1) Create a connection with the hosted catalog

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

RisingWave just spun up a fully spec-compliant **Iceberg catalog** inside its own metadata store—no Glue, Nessie, or external Postgres required.

## 2) Build the streaming pipeline and write to Iceberg

### Create Kafka sources (7 topics)

```sql
CREATE SOURCE trucks (
  truck_id integer,
  truck_model varchar,
  capacity_tons integer,
  manufacture_year integer,
  current_location varchar
  ) WITH (
    connector = 'kafka',
    topic = 'trucks',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE driver (
  driver_id integer,
  driver_name varchar,
  license_number varchar,
  assigned_truck_id integer
  ) WITH (
    connector = 'kafka',
    topic = 'drivers',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE shipments (
  shipment_id varchar,
  origin varchar,
  destination varchar,
  shipment_weight integer,
  truck_id integer
  ) WITH (
    connector = 'kafka',
    topic = 'shipments',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE warehouses (
  warehouse_id varchar,
  location varchar,
  capacity_tons integer
  ) WITH (
    connector = 'kafka',
    topic = 'warehouses',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE route (
  route_id varchar,
  truck_id integer,
  driver_id integer,
  estimated_departure_time timestamptz,
  estimated_arrival_time timestamptz,
  distance_km integer
  ) WITH (
    connector = 'kafka',
    topic = 'route',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE fuel (
  fuel_log_id varchar,
  truck_id integer,
  fuel_date timestamptz,
  liters_filled integer,
  fuel_station varchar
  ) WITH (
    connector = 'kafka',
    topic = 'fuel',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE maint (
  maintenance_id varchar,
  truck_id integer,
  maintenance_date timestamptz,
  cost_usd integer
  ) WITH (
    connector = 'kafka',
    topic = 'maint',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

### Join all the sources in a materialized view

```sql
create materialized view logistics_joined_mv as
select
    t.truck_id,
    d.driver_id,
    d.driver_name,
    d.license_number,
    t.truck_model,
    t.capacity_tons, 
    t.current_location,
    s.shipment_id,
    s.origin,
    w.location as warehouse_location,
    w.capacity_tons as warehouse_capacity_tons,
    r.route_id,
    r.estimated_departure_time,
    r.distance_km,
    f.fuel_log_id,
    f.fuel_date,
    f.liters_filled,
    m.maintenance_id,
    m.maintenance_date,
    m.cost_usd
from driver d
left join
    trucks t on d.assigned_truck_id = t.truck_id
join 
    shipments s on t.truck_id = s.truck_id
join 
    route r on r.truck_id = t.truck_id
join
    warehouses w on s.destination = w.location
join 
    fuel f on f.truck_id = t.truck_id
join
    maint m on m.truck_id = t.truck_id;
```

Quick peek:

```sql
select * from logistics_joined_mv limit 5;
```

### Enable Iceberg engine and create the Iceberg table

```sql
-- Use the connection
SET iceberg_engine_connection = 'public.my_iceberg_connection';
```

```sql
CREATE TABLE logistics_joined_iceberg (  
  truck_id                  INT,
  driver_id                 INT,
  driver_name               VARCHAR,
  license_number            VARCHAR,
  truck_model               VARCHAR,
  capacity_tons             INT,
  current_location          VARCHAR,

  shipment_id               VARCHAR,
  origin                    VARCHAR,

  warehouse_location        VARCHAR,
  warehouse_capacity_tons   INT,

  route_id                  VARCHAR,
  estimated_departure_time  TIMESTAMPTZ,
  distance_km               INT,

  fuel_log_id               VARCHAR,
  fuel_date                 TIMESTAMPTZ,
  liters_filled             INT,

  maintenance_id            VARCHAR,
  maintenance_date          TIMESTAMPTZ,
  cost_usd                  INT
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg; 
```

### Stream the joined results into Iceberg

```sql
INSERT INTO logistics_joined_iceberg
SELECT * 
FROM logistics_joined_mv;
```

Query the Iceberg table to see the results:

```sql
select * from logistics_joined_iceberg limit 5;
```

## 3) Query the Iceberg table via Spark

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

If you see a “region not specified” error, set the region before running Spark:

```bash
export AWS_REGION=us-east-1
```

Now, run this to connect with Spark:

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
select * from dev.public.logistics_joined_iceberg;
```

## Optional: Clean up (Docker)

> ⚠️ Only run this after you’ve fully tested.
>
> * `-v` deletes Docker **volumes** (all persisted data), in addition to stopping and removing containers and networks.

**If you want a full cleanup (including volumes/data):**

```bash
docker compose down -v
```

## Recap

* **Provision** an Iceberg catalog: set `hosted_catalog = true`.
* **Join** seven streaming topics into a single **materialized view** and **write** to an Iceberg table with `ENGINE = iceberg`.
* **Query** the data from RisingWave or any Iceberg-aware engine (Spark), no lock-in, no extra services.

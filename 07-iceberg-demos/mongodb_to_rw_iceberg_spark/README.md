# MongoDB CDC → Iceberg (via RisingWave) → Query with Spark

RisingWave ingests MongoDB CDC through its `mongodb-cdc` source and writes to **Apache Iceberg** using the Iceberg Table Engine. **Spark SQL** then queries the continuously updated table.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/mongodb_to_rw_iceberg_spark

# Launch demo stack
docker compose up -d
````
The **Compose** file starts **Lakekeeper** at `127.0.0.1:8181` and provisions the Lakekeeper warehouse, **RisingWave** at `127.0.0.1:4566`, **MongoDB** at `127.0.0.1:27017` (replica set), and a **MinIO** object store at `127.0.0.1:9301`, so you can follow the next steps exactly as written.

## 1. Prepare MongoDB (seed data + CDC changes)

Initialize (or verify) the replica set and seed data.

### A) If your stack includes `config-replica.js` (recommended)

Create a file named **`config-replica.js`** in this folder:

```javascript
// config-replica.js
rs.initiate({ _id: "rs0", members: [ { _id: 0, host: "mongodb:27017" } ] })
rs.status()
```

Your compose will run this automatically on startup.

### B) Seed data and simulate CDC

Connect to MongoDB:

```bash
docker exec -it mongodb mongo
```

Seed the `mydb.ecommerce_orders` collection:

```javascript
use mydb

db.ecommerce_orders.insertMany([
  {
    _id: ObjectId(),
    order_id: 202508260101,
    customer_id: 5001001,
    items_total: 84.23,
    currency: "USD",
    payment_method: "card",
    channel: "web",
    shipping_city: "Seattle",
    shipping_state: "WA",
    shipping_country: "US",
    status: "pending",
    is_expedited: false
  },
  {
    _id: ObjectId(),
    order_id: 202508260102,
    customer_id: 5001001,
    items_total: 52.10,
    currency: "USD",
    payment_method: "card",
    channel: "web",
    shipping_city: "San Jose",
    shipping_state: "CA",
    shipping_country: "US",
    status: "paid",
    is_expedited: false
  },
  {
    _id: ObjectId(),
    order_id: 202508260103,
    customer_id: 5002002,
    items_total: 1299.99,
    currency: "USD",
    payment_method: "card",
    channel: "app",
    shipping_city: "Austin",
    shipping_state: "TX",
    shipping_country: "US",
    status: "pending",
    is_expedited: false
  },
  {
    _id: ObjectId(),
    order_id: 202508260104,
    customer_id: 5003003,
    items_total: 35.00,
    currency: "USD",
    payment_method: "wallet",
    channel: "app",
    shipping_city: "Boston",
    shipping_state: "MA",
    shipping_country: "US",
    status: "shipped",
    is_expedited: true
  }
])
```

Simulate CDC (updates + a new insert):

```javascript
use mydb

// pending -> paid
db.ecommerce_orders.updateOne(
  { order_id: 202508260101, status: "pending" },
  { $set: { status: "paid" } }
)

// pending -> canceled, flag expedited false
db.ecommerce_orders.updateOne(
  { order_id: 202508260103, status: "pending" },
  { $set: { status: "canceled", is_expedited: false } }
)

// new order (declared as shipped & expedited)
db.ecommerce_orders.insertOne({
  _id: ObjectId(),
  order_id: 202508260105,
  customer_id: 5002002,
  items_total: 42.00,
  currency: "USD",
  payment_method: "card",
  channel: "web",
  shipping_city: "New York",
  shipping_state: "NY",
  shipping_country: "US",
  status: "shipped",
  is_expedited: true
})

// sanity check
db.ecommerce_orders.find().sort({ order_id: 1 }).limit(10).pretty()
```

## 2. Create the CDC source and Iceberg table in RisingWave

Connect to RisingWave with `psql`:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create the **raw CDC table** that ingests MongoDB change streams (captures `_id`, full `payload`, plus upstream commit timestamp via `INCLUDE TIMESTAMP`):

```sql
CREATE TABLE ecommerce_orders_raw (
  _id     JSONB PRIMARY KEY,
  payload JSONB
)
INCLUDE TIMESTAMP AS commit_ts
WITH (
  connector       = 'mongodb-cdc',
  mongodb.url     = 'mongodb://mongodb:27017/?replicaSet=rs0',
  collection.name = 'mydb.ecommerce_orders'
);
```

Project typed columns from `payload` into a SQL-friendly source table:

```sql
CREATE TABLE ecommerce_orders_src AS
SELECT
  COALESCE(
    (payload->'order_id'->>'$numberLong')::numeric,
    (payload->>'order_id')::numeric
  )::bigint                                   AS order_id,
  COALESCE(
    (payload->'customer_id'->>'$numberLong')::numeric,
    (payload->>'customer_id')::numeric
  )::bigint                                   AS customer_id,
  (payload->>'items_total')::numeric          AS items_total,
  payload->>'currency'                        AS currency,
  payload->>'payment_method'                  AS payment_method,
  payload->>'channel'                         AS channel,
  payload->>'shipping_city'                   AS shipping_city,
  payload->>'shipping_state'                  AS shipping_state,
  payload->>'shipping_country'                AS shipping_country,
  payload->>'status'                          AS status,
  (payload->>'is_expedited')::boolean         AS is_expedited,
  commit_ts
FROM ecommerce_orders_raw;
```

Create an **Iceberg connection** using **hosted\_catalog** (no Glue/Nessie/JDBC to run) and activate it:

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

SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';
```

Create the **Iceberg table** from the normalized source and load data:

```sql
CREATE TABLE ecommerce_orders_iceberg (
  order_id         BIGINT PRIMARY KEY,
  customer_id      BIGINT,
  items_total      NUMERIC,
  currency         VARCHAR,
  payment_method   VARCHAR,
  channel          VARCHAR,
  shipping_city    VARCHAR,
  shipping_state   VARCHAR,
  shipping_country VARCHAR,
  status           VARCHAR,
  is_expedited     BOOLEAN,
  commit_ts        TIMESTAMPTZ
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;

INSERT INTO ecommerce_orders_iceberg
SELECT * FROM ecommerce_orders_src;

-- quick peek
SELECT * FROM ecommerce_orders_iceberg ORDER BY order_id LIMIT 5;
```

> Why this works
>
> * `mongodb-cdc` reads change streams into a JSONB `payload` plus a metadata timestamp.
> * We cast JSON to typed SQL columns.
> * The **Iceberg table engine** stores data in open Iceberg format that any compatible engine can read.

## 3. Query the Iceberg table via Spark

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

### 5. Configure & run Spark SQL (Iceberg + MinIO + JDBC)
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
Query the table:

```sql
SELECT * FROM public.ecommerce_orders_iceberg LIMIT 5;
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

* **Capture**: Logical CDC from MongoDB into RisingWave with `mongodb-cdc`.
* **Model**: Project typed columns from JSONB using `->` / `->>` and casts.
* **Store**: Stream into an Iceberg table via the Iceberg table engine; manage metadata with the self-hosted catalog.
* **Query**: Point Spark at the same catalog + warehouse and run SQL over fresh, open-format data.

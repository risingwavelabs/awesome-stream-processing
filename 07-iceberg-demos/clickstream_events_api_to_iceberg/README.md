# Real-Time Clickstream Analytics to Apache Iceberg with RisingWave + Events API — No Kafka Required
This demo shows how to ingest real-time clickstream data from an online platform over HTTP using the **RisingWave Events API** (JSON/NDJSON), enrich it with related context (users, sessions, devices, campaigns, and page metadata), compute live analytics with **RisingWave materialized views**, and continuously write the results to an **Apache Iceberg** table.

**No Kafka required:** Instead of streaming events through Kafka topics, the demo shows how you can push events directly to RisingWave via HTTP, then writes the processed results to Iceberg. The Iceberg catalog is provided by a **self-hosted, REST-based Lakekeeper** service, and the table data is stored in MinIO, keeping everything query-ready for Spark, Trino, or any Iceberg-aware engine.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/) (to connect to RisingWave)

## Clone the repo and start the stack

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/07-iceberg-demos/clickstream_events_api_to_iceberg

# Launch demo stack
docker compose up -d
```

The **Compose** file starts:

- **Lakekeeper** at `127.0.0.1:8181` (REST Iceberg catalog) and provisions the warehouse
- **RisingWave** at `127.0.0.1:4566`
- **MinIO** at `127.0.0.1:9301` (S3-compatible object store)
- **Events API** at `127.0.0.1:8000` (HTTP ingestion + HTTP SQL)
- A **clickstream HTTP producer** that generates realistic traffic and sends **NDJSON batches** to Events API

## 1) Create a connection with the hosted catalog

Connect to RisingWave:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create an Iceberg connection (Lakekeeper REST catalog + MinIO):

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

This gives RisingWave a fully spec-compliant **Iceberg REST catalog** (Lakekeeper) without Glue/Nessie/external catalog services.

## 2) Build the streaming pipeline and write to Iceberg

### Create clickstream tables (ingested via Events API)

This demo uses **plain RisingWave tables** (append-only for simplicity). The HTTP producer inserts into these tables via:

- `POST /v1/events?name=<table>` (JSON / NDJSON)
- `POST /v1/sql` (execute DDL/DML over HTTP)

Create the tables:

```sql
-- Users
CREATE TABLE IF NOT EXISTS users (
  user_id BIGINT,
  full_name VARCHAR,
  email VARCHAR,
  country VARCHAR,
  signup_time TIMESTAMPTZ,
  marketing_opt_in BOOLEAN,
  ingested_at TIMESTAMPTZ
);

-- Devices
CREATE TABLE IF NOT EXISTS devices (
  device_id VARCHAR,
  device_type VARCHAR,
  os VARCHAR,
  browser VARCHAR,
  user_agent VARCHAR,
  ingested_at TIMESTAMPTZ
);

-- Sessions 
CREATE TABLE IF NOT EXISTS sessions (
  session_id VARCHAR,
  user_id BIGINT,
  device_id VARCHAR,
  session_start TIMESTAMPTZ,
  ip_address VARCHAR,
  geo_city VARCHAR,
  geo_region VARCHAR,
  ingested_at TIMESTAMPTZ
);

-- Campaigns 
CREATE TABLE IF NOT EXISTS campaigns (
  campaign_id VARCHAR,
  source VARCHAR,
  medium VARCHAR,
  campaign VARCHAR,
  content VARCHAR,
  term VARCHAR,
  ingested_at TIMESTAMPTZ
) WITH (appendonly = 'true');

-- Page catalog
CREATE TABLE IF NOT EXISTS page_catalog (
  page_url VARCHAR,
  page_category VARCHAR,
  product_id VARCHAR,
  product_category VARCHAR,
  ingested_at TIMESTAMPTZ
) WITH (appendonly = 'true');

-- Clickstream events
CREATE TABLE IF NOT EXISTS clickstream_events (
  event_id VARCHAR,
  user_id BIGINT,
  session_id VARCHAR,
  event_type VARCHAR,         -- page_view/click/add_to_cart/checkout_start/purchase
  page_url VARCHAR,
  element_id VARCHAR,
  event_time TIMESTAMPTZ,     -- client event time
  referrer VARCHAR,
  campaign_id VARCHAR,
  revenue_usd DOUBLE PRECISION,
  ingested_at TIMESTAMPTZ     -- ingest time
);
```

### Join all sources in a materialized view

This MV creates a continuously updated, enriched clickstream stream by joining:

events → users → sessions → devices → pages → campaigns.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS clickstream_joined_mv AS
SELECT
  e.event_id,
  e.event_time,
  e.ingested_at,
  e.event_type,

  e.user_id,
  u.full_name,
  u.country,
  u.marketing_opt_in,

  s.session_id,
  s.session_start,
  s.geo_city,
  s.geo_region,

  d.device_type,
  d.os,
  d.browser,

  e.page_url,
  p.page_category,
  p.product_id,
  p.product_category,

  e.element_id,
  e.referrer,

  c.source AS campaign_source,
  c.medium AS campaign_medium,
  c.campaign AS campaign_name,
  c.content AS campaign_content,
  c.term AS campaign_term,

  e.revenue_usd
FROM clickstream_events e
LEFT JOIN users u        ON e.user_id = u.user_id
LEFT JOIN sessions s     ON e.session_id = s.session_id
LEFT JOIN devices d      ON s.device_id = d.device_id
LEFT JOIN page_catalog p ON e.page_url = p.page_url
LEFT JOIN campaigns c    ON e.campaign_id = c.campaign_id;

```

Quick peek:

```sql
SELECT * FROM clickstream_joined_mv ORDER BY event_time DESC LIMIT 10;
```

### Create a real-time session KPI + funnel MV

This MV continuously computes per-session engagement and conversion signals.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS session_kpi_mv AS
SELECT
  s.session_id,
  s.user_id,
  u.country,
  d.device_type,

  MIN(e.event_time) AS first_event_time,
  MAX(e.event_time) AS last_event_time,
  EXTRACT(EPOCH FROM (MAX(e.event_time) - MIN(e.event_time)))::BIGINT AS session_duration_seconds,

  SUM(CASE WHEN e.event_type = 'page_view' THEN 1 ELSE 0 END) AS page_views,
  SUM(CASE WHEN e.event_type = 'click' THEN 1 ELSE 0 END) AS clicks,
  SUM(CASE WHEN e.event_type = 'add_to_cart' THEN 1 ELSE 0 END) AS add_to_cart,
  SUM(CASE WHEN e.event_type = 'checkout_start' THEN 1 ELSE 0 END) AS checkout_start,
  SUM(CASE WHEN e.event_type = 'purchase' THEN 1 ELSE 0 END) AS purchases,

  COALESCE(SUM(e.revenue_usd), 0) AS revenue_usd,

  CASE WHEN SUM(CASE WHEN e.event_type='add_to_cart' THEN 1 ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS did_add_to_cart,
  CASE WHEN SUM(CASE WHEN e.event_type='purchase' THEN 1 ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS did_purchase
FROM sessions s
LEFT JOIN clickstream_events e ON e.session_id = s.session_id
LEFT JOIN users u       ON s.user_id = u.user_id
LEFT JOIN devices d     ON s.device_id = d.device_id
GROUP BY
  s.session_id, s.user_id, u.country, d.device_type;
```

Query it:

```sql
SELECT * FROM session_kpi_mv ORDER BY revenue_usd DESC LIMIT 10;
```

### Enable Iceberg engine and create the Iceberg table

```sql
-- Use the connection
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';
```

Create the Iceberg sink table:

```sql
CREATE TABLE IF NOT EXISTS clickstream_joined_iceberg (
  event_id VARCHAR,
  event_time TIMESTAMPTZ,
  ingested_at TIMESTAMPTZ,
  event_type VARCHAR,

  user_id BIGINT,
  full_name VARCHAR,
  country VARCHAR,
  marketing_opt_in BOOLEAN,

  session_id VARCHAR,
  session_start TIMESTAMPTZ,
  geo_city VARCHAR,
  geo_region VARCHAR,

  device_type VARCHAR,
  os VARCHAR,
  browser VARCHAR,

  page_url VARCHAR,
  page_category VARCHAR,
  product_id VARCHAR,
  product_category VARCHAR,

  element_id VARCHAR,
  referrer VARCHAR,

  campaign_source VARCHAR,
  campaign_medium VARCHAR,
  campaign_name VARCHAR,
  campaign_content VARCHAR,
  campaign_term VARCHAR,

  revenue_usd DOUBLE PRECISION
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;
```

### Stream data into Iceberg

```sql
INSERT INTO clickstream_joined_iceberg
SELECT * FROM clickstream_joined_mv;
```

Query the Iceberg table:

```sql
SELECT * FROM clickstream_joined_iceberg ORDER BY event_time DESC LIMIT 10;
```

## Some useful “real-time clickstream” queries

### Live traffic (last 5 minutes)

```sql
SELECT
  date_trunc('minute', event_time) AS minute,
  COUNT(*) AS events,
  SUM(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS purchases,
  SUM(COALESCE(revenue_usd, 0)) AS revenue
FROM clickstream_events
WHERE event_time > now() - interval '5 minutes'
GROUP BY 1
ORDER BY 1 DESC;
```

### Top pages now

```sql
SELECT page_url, COUNT(*) AS views
FROM clickstream_joined_mv
WHERE event_type='page_view'
  AND event_time > now() - interval '10 minutes'
GROUP BY page_url
ORDER BY views DESC
LIMIT 10;
```

### Conversion by device

```sql
SELECT
  device_type,
  COUNT(*) FILTER (WHERE did_purchase) AS converted_sessions,
  COUNT(*) AS sessions,
  ROUND(100.0 * COUNT(*) FILTER (WHERE did_purchase) / NULLIF(COUNT(*),0), 2) AS conversion_rate_pct
FROM session_kpi_mv
GROUP BY device_type
ORDER BY conversion_rate_pct DESC;
```

## 3) Validate ingestion via Events API (optional)

Events API is exposed on `http://localhost:8000`.

### Create tables via HTTP SQL

```bash
curl -X POST \
  -d 'SELECT 1;' \
  http://localhost:8000/v1/sql
```

### Ingest a single JSON event

```bash
curl -X POST \
  -d '{"event_id":"EVT-00000001","user_id":123,"session_id":"SESS-1","event_type":"page_view","page_url":"/","element_id":"","event_time":"2026-01-01T10:00:00Z","referrer":"https://google.com","campaign_id":"CMP-000000","revenue_usd":0,"ingested_at":"2026-01-01T10:00:01Z"}' \
  'http://localhost:8000/v1/events?name=clickstream_events'
```

### Ingest NDJSON (batch)

```bash
curl -X POST \
  --data-binary @- \
  'http://localhost:8000/v1/events?name=clickstream_events' << 'EOF'
{"event_id":"EVT-00000002","user_id":123,"session_id":"SESS-1","event_type":"click","page_url":"/products/laptop","element_id":"cta_details","event_time":"2026-01-01T10:00:05Z","referrer":"","campaign_id":"CMP-000000","revenue_usd":0,"ingested_at":"2026-01-01T10:00:06Z"}
{"event_id":"EVT-00000003","user_id":123,"session_id":"SESS-1","event_type":"purchase","page_url":"/checkout","element_id":"purchase_confirm","event_time":"2026-01-01T10:01:00Z","referrer":"","campaign_id":"CMP-000000","revenue_usd":199.99,"ingested_at":"2026-01-01T10:01:01Z"}
EOF
```

## 4) Query the Iceberg table via Spark

Install Spark and set up all the required dependencies as shown in this [demo](https://github.com/risingwavelabs/awesome-stream-processing/tree/main/07-iceberg-demos/streaming_iceberg_quickstart#install-apache-spark-if-not-installed) to run Spark SQL:

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

Then query the Iceberg table:

```sql
SELECT * FROM public.clickstream_joined_iceberg LIMIT 5;
```

## Clean up (Docker)

> ⚠️ Only run this after you’ve fully tested.
> 
> - `v` deletes Docker volumes (all persisted data) in addition to stopping/removing containers and networks.

```bash
docker compose down -v
```

## Recap

- **Spin up an open Iceberg stack**: Lakekeeper (REST catalog) + MinIO (S3-compatible storage) + RisingWave.
- **Ingest clickstream over HTTP (no Kafka)** using the RisingWave **Events API**, with both **JSON** and high-throughput **NDJSON** batches.
- **Enrich and analyze in real time** by combining events with user/session/device/campaign/page context and computing live metrics with **materialized views** (e.g., session KPIs and funnels).
- **Continuously write results to Apache Iceberg** using `ENGINE = iceberg`, keeping the table query-ready at all times.
- **Query anywhere**: read the same Iceberg table from RisingWave or external engines like **Spark**/**Trino** with minimal extra services and no vendor lock-in.

# Build Real-Time Dynamic Pricing & **Live Inventory** with RisingWave
This demo showcases a real-time dynamic pricing pipeline for a retail scenario (purchases, restocks, inventory snapshots, and competitor price signals) and, optionally, writes sales KPIs to an Apache Iceberg table. It spins up a Docker stack, streams synthetic retail events into Kafka, and lets RisingWave ingest them via Kafka topics and Postgres CDC to compute live inventory (base stock plus or minus per-minute purchases and restocks), model demand and competitor pressure, and derive dynamic prices with plain SQL, keeping everything query-ready for Spark, Trino, or any other engine. It uses RisingWave with a self-hosted, REST-based Lakekeeper catalog to create Iceberg tables without any additional external services.

## Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Launch the demo cluster

### 1) Clone the demo repo and start the stack
```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/03-solution-demos/live-inventory-management-and-dynamic-pricing

# Launch demo stack
docker compose up -d
```

### 2) Connect to RisingWave (psql)
```bash
psql -h localhost -p 4566 -d dev -U root
```

## 1. Create streaming sources (Kafka) & CDC (Postgres)

### Kafka sources
```sql
CREATE SOURCE web_clicks (
  event_time timestamptz,
  product_id int,
  event_type varchar   -- 'view'|'add_to_cart'|'remove_from_cart'
) WITH (
  connector = 'kafka',
  topic = 'web_clicks',
  properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE competitor_prices (
  ts timestamptz,
  product_id int,
  competitor varchar,
  competitor_price numeric
) WITH (
  connector = 'kafka',
  topic = 'competitor_prices',
  properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE purchases (
  purchase_time timestamptz,
  product_id int,
  quantity_purchased int,
  customer_id varchar
) WITH (
  connector = 'kafka',
  topic = 'purchases',
  properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE restocks (
  restock_time timestamptz,
  product_id int,
  quantity_restocked int
) WITH (
  connector = 'kafka',
  topic = 'restocks',
  properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

```

### Postgres CDC source
```sql
CREATE SOURCE postgres_cdc
WITH (
  connector       = 'postgres-cdc',
  hostname        = 'postgres',   -- container name from docker-compose
  port            = '5432',
  username        = 'myuser',
  password        = '123456',
  database.name   = 'mydb',
  schema.name     = 'public',
  publication.name= 'rw_publication'
);
```

## 2. Mirror base tables from CDC into RisingWave tables
```sql
-- Product catalog mirrored from Postgres CDC
CREATE TABLE product_inventory (
  "product_id" INT PRIMARY KEY,
  "product_name" varchar,
  "stock_level" int,
  "reorder_threshold" int,
  "supplier" varchar,
  "base_price" decimal
)
FROM postgres_cdc TABLE 'public.product_inventory';

SELECT * FROM product_inventory LIMIT 5;

-- Orders mirrored from Postgres CDC
CREATE TABLE orders (
  order_id     INT PRIMARY KEY,
  order_time   TIMESTAMPTZ,
  product_id   INT,
  quantity     INT,
  customer_id  VARCHAR
)
FROM postgres_cdc TABLE 'public.orders';

SELECT * FROM orders LIMIT 5;
```

## 3. Materialized views (the core logic)

These **six** MVs cover *all* inputs (Kafka + CDC) and explain the dynamic-pricing and live Inventory story end-to-end.

### MV 1 — Minute join of purchases & restocks (inventory deltas)
```sql
CREATE MATERIALIZED VIEW minute_join AS
SELECT
  COALESCE(p.product_id, r.product_id)      AS product_id,
  COALESCE(p.window_start, r.window_start)  AS window_start,
  COALESCE(p.total_purchased, 0)            AS total_purchased,
  COALESCE(r.total_restocked, 0)            AS total_restocked
FROM (
  SELECT product_id, window_start, SUM(quantity_purchased) AS total_purchased
  FROM TUMBLE(purchases, purchase_time, INTERVAL '1 MINUTE')
  GROUP BY product_id, window_start
) p
FULL JOIN (
  SELECT product_id, window_start, SUM(quantity_restocked) AS total_restocked
  FROM TUMBLE(restocks, restock_time, INTERVAL '1 MINUTE')
  GROUP BY product_id, window_start
) r
ON p.product_id = r.product_id AND p.window_start = r.window_start;
```

### MV 2 — Live stock state (base stock + net flows) using CDC product master
```sql
CREATE MATERIALIZED VIEW product_stock_status AS
WITH inventory_updates AS (
  SELECT
    b.product_id,
    b.product_name,
    b.base_price,
    b.reorder_threshold,
    mj.window_start,
    -- cumulative restocks − purchases + base stock
    SUM(COALESCE(mj.total_restocked, 0))
      OVER (PARTITION BY b.product_id ORDER BY mj.window_start)
  - SUM(COALESCE(mj.total_purchased, 0))
      OVER (PARTITION BY b.product_id ORDER BY mj.window_start)
  + b.stock_level AS current_inventory
  FROM product_inventory b
  LEFT JOIN minute_join mj
    ON b.product_id = mj.product_id
)
SELECT
  product_id,
  product_name,
  window_start AS inventory_window,
  current_inventory,
  base_price,
  reorder_threshold,
  CASE
    WHEN current_inventory < 20 THEN 'Low'
    WHEN current_inventory BETWEEN 20 AND 50 THEN 'Medium'
    ELSE 'High'
  END AS stock_level_category
FROM inventory_updates;
```

### MV 3 — Web demand proxy (clicks per minute)
```sql
CREATE MATERIALIZED VIEW web_clicks_minutely AS
SELECT
  product_id,
  window_start,
  COUNT(*) AS clicks
FROM TUMBLE(web_clicks, event_time, INTERVAL '1 MINUTE')
GROUP BY product_id, window_start;
```

### MV 4 — Latest competitor price per (product, competitor)
```sql
CREATE MATERIALIZED VIEW competitor_latest AS
SELECT product_id, competitor, competitor_price, ts
FROM (
  SELECT
    product_id,
    competitor,
    competitor_price,
    ts,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, competitor
      ORDER BY ts DESC
    ) AS rn
  FROM competitor_prices
) t
WHERE rn = 1;
```

### MV 5 — Dynamic pricing (stock rule + demand & competitor floor)
```sql
CREATE MATERIALIZED VIEW dynamic_pricing_enriched AS
WITH demand AS (
  SELECT
    product_id,
    window_start,
    SUM(clicks) OVER (
      PARTITION BY product_id
      ORDER BY window_start
      RANGE BETWEEN INTERVAL '15 MINUTE' PRECEDING AND CURRENT ROW
    ) AS clicks_15m
  FROM web_clicks_minutely
),
comp_min AS (
  SELECT product_id, MIN(competitor_price) AS min_competitor_price
  FROM competitor_latest
  GROUP BY product_id
)
SELECT
  s.product_id,
  s.product_name,
  s.inventory_window,
  s.current_inventory,
  s.stock_level_category,
  s.base_price,
  d.clicks_15m,
  c.min_competitor_price,
  -- Base stock rule
  CASE
    WHEN s.stock_level_category = 'Low'    THEN ROUND(s.base_price * 1.20, 2)
    WHEN s.stock_level_category = 'Medium' THEN s.base_price
    WHEN s.stock_level_category = 'High'   THEN ROUND(s.base_price * 0.90, 2)
  END AS stock_rule_price,
  -- Final price: tweak by demand & competitor undercut, clamp at 0.5x base
  GREATEST(
    ROUND(
      CASE
        WHEN c.min_competitor_price IS NOT NULL
             AND s.base_price <= c.min_competitor_price
             AND COALESCE(d.clicks_15m, 0) > 30
          THEN
            (CASE
               WHEN s.stock_level_category = 'Low'    THEN s.base_price * 1.20
               WHEN s.stock_level_category = 'Medium' THEN s.base_price
               ELSE                                     s.base_price * 0.90
             END) * 1.02
        WHEN c.min_competitor_price IS NOT NULL
             AND
             (CASE
               WHEN s.stock_level_category = 'Low'    THEN s.base_price * 1.20
               WHEN s.stock_level_category = 'Medium' THEN s.base_price
               ELSE                                     s.base_price * 0.90
             END) > c.min_competitor_price
          THEN
            (CASE
               WHEN s.stock_level_category = 'Low'    THEN s.base_price * 1.20
               WHEN s.stock_level_category = 'Medium' THEN s.base_price
               ELSE                                     s.base_price * 0.90
             END) * 0.99
        ELSE
          (CASE
             WHEN s.stock_level_category = 'Low'    THEN s.base_price * 1.20
             WHEN s.stock_level_category = 'Medium' THEN s.base_price
             ELSE                                     s.base_price * 0.90
           END)
      END, 2),
    ROUND(0.5 * s.base_price, 2)
  ) AS final_price
FROM product_stock_status s
LEFT JOIN demand   d ON d.product_id  = s.product_id AND d.window_start = s.inventory_window
LEFT JOIN comp_min c ON c.product_id  = s.product_id;
```

### MV 6 — Sales & revenue (orders CDC joined to price timeline)
```sql
CREATE MATERIALIZED VIEW sales_profit AS
SELECT
  o.product_id,
  MAX(pi.product_name) AS product_name,
  SUM(o.quantity)      AS total_orders,
  CAST(SUM(dp.final_price * o.quantity) AS DECIMAL) AS revenue_estimate
FROM orders o
ASOF LEFT JOIN dynamic_pricing_enriched dp
  ON o.product_id = dp.product_id
 AND o.order_time >= dp.inventory_window
LEFT JOIN product_inventory pi
  ON pi.product_id = o.product_id
GROUP BY o.product_id;
```

## Optional: Persist Sales KPIs to Iceberg (from `sales_profit` MV)
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

-- Use the Lakekeeper connection
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';

-- Create an Iceberg table to persist sales KPIs
CREATE TABLE sales_profit_iceberg (
  product_id        INT,
  product_name      VARCHAR,
  total_orders      BIGINT,
  revenue_estimate  DOUBLE PRECISION
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;

-- Stream data from the MV into the Iceberg table
INSERT INTO sales_profit_iceberg
SELECT
  product_id,
  product_name,
  total_orders,
  revenue_estimate::DOUBLE PRECISION 
FROM sales_profit;

-- Quick peek
SELECT * FROM sales_profit_iceberg LIMIT 5;
```

## Optional: Clean up
```bash
docker compose down -v
```

## Recap
- **Ingest** retail events from Kafka and tables from Postgres via CDC.
- **Compute** live inventory continuously from base stock and per-minute deltas.
- **Layer** demand signals and competitor pressure.
- **Price** products dynamically and **track** sales and revenue.
- **Persist** KPIs to Iceberg using the Lakekeeper REST catalog for long-term storage and cross-engine queries **(optional)**.

-- RisingWave SQL to stream data from Kafka to Iceberg and enable ClickHouse reads
-- This example demonstrates streaming ingestion with Iceberg storage
\set ECHO queries
\pset pager off
\set GREEN '\033[0;32m'
\set YELLOW '\033[1;33m'
\set BLUE '\033[0;34m'
\set NC '\033[0m'

\echo :GREEN
\echo '======================================='
\echo 'RisingWave Demo: Kafka → Iceberg → ClickHouse Query'
\echo
\echo 'Please make sure you have run ./prepare.sh to set up the environment'
\echo '======================================='
\echo :YELLOW
\prompt 'Press Enter to start Step 1 (Create Lakekeeper connection)...' dummy

\echo :GREEN
\echo '=== Step 1: Create connection to Lakekeeper catalog for Iceberg access ==='
\echo :BLUE
CREATE CONNECTION IF NOT EXISTS lakekeeper_catalog_conn
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

\echo :GREEN
\echo 'Step 1 completed: Lakekeeper connection created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 2 (Set Iceberg engine connection)...' dummy

\echo :GREEN
\echo '=== Step 2: Set Iceberg engine connection ==='
\echo :BLUE
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';

\echo :GREEN
\echo 'Step 2 completed: Iceberg engine connection set'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 3 (Create Kafka source)...' dummy

\echo :GREEN
\echo '=== Step 3: Create Kafka source for streaming sales data ==='
\echo :BLUE
CREATE SOURCE streaming_sales_kafka (
    sale_id INTEGER,
    user_id INTEGER,
    product_id INTEGER,
    product_name VARCHAR,
    sale_timestamp TIMESTAMPTZ,
    quantity INTEGER,
    unit_price INTEGER,
    total_price INTEGER,
    currency VARCHAR,
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER
) INCLUDE timestamp AS ingestion_time
WITH (
    connector = 'kafka',
    topic = 'sales-stream',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'latest'
) FORMAT PLAIN ENCODE JSON;

\echo :GREEN
\echo 'Step 3 completed: Kafka source created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 4 (Create Iceberg table)...' dummy

\echo :GREEN
\echo '=== Step 4: Create Iceberg table for sales data ==='
\echo :BLUE
CREATE TABLE iceberg_sales (
    sale_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    product_id INTEGER,
    product_name VARCHAR,
    sale_timestamp TIMESTAMP,
    quantity INTEGER,
    unit_price INTEGER,
    total_price INTEGER,
    currency VARCHAR DEFAULT 'USD',
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER DEFAULT 0,
    ingestion_time TIMESTAMP
) WITH (
    commit_checkpoint_interval = 1,
    compaction_interval_sec = 5,
    snapshot_expiration_max_age_millis = 0,
    write_mode = 'copy-on-write',
)
ENGINE = iceberg;

\echo :GREEN
\echo 'Step 4 completed: Iceberg table created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 5 (Create streaming sink)...' dummy

\echo :GREEN
\echo '=== Step 5: Create sink to continuously stream data from Kafka into Iceberg ==='
\echo :BLUE
CREATE SINK streaming_sales_ingestion INTO iceberg_sales AS
SELECT 
    sale_id,
    user_id,
    product_id,
    product_name,
    sale_timestamp::timestamp,
    quantity,
    unit_price,
    total_price,
    COALESCE(currency, 'USD') as currency,
    store_id,
    region,
    payment_method,
    COALESCE(discount_amount, 0) as discount_amount,
    ingestion_time::timestamp
FROM streaming_sales_kafka;

\echo :GREEN
\echo 'Step 5 completed: Streaming sink created'
\echo :YELLOW
\prompt 'Wait for a few seconds. Press Enter to verify data ingestion...' dummy

\echo :GREEN
\echo '=== Verify data ingestion ==='
\echo :BLUE
SELECT COUNT(*) AS record_count 
FROM iceberg_sales;

\echo :GREEN
\echo '=== Check recent sales activity ==='
\echo :BLUE
SELECT * FROM iceberg_sales ORDER BY ingestion_time DESC LIMIT 10;

\echo :GREEN
\echo 'Data verification completed'
\echo :YELLOW
\prompt 'Press Enter to to exit...' dummy

\echo
\echo '======================================='
\echo 'Demo completed successfully!'
\echo 'Kafka stream is now flowing into Iceberg table'
\echo 'Data is ready for ClickHouse analytics'
\echo 'You can watch the query results via'
\echo '  • ./client.sh watch-ch'
\echo '======================================='
\echo :NC
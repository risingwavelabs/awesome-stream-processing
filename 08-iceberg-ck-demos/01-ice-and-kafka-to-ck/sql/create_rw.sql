-- RisingWave SQL to ingest historical data from Iceberg and stream data from Kafka
-- This example uses a sales table schema to demonstrate the pattern
\set ECHO queries
\pset pager off

\echo
\echo '======================================='
\echo 'RisingWave Demo: Iceberg + Kafka → ClickHouse Table'
\echo '======================================='
\echo
\prompt 'Press Enter to start Step 1 (Create Lakekeeper connection)...' dummy

\echo
\echo '=== Step 1: Create connection to Lakekeeper catalog for Iceberg access ==='
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

\echo 'Step 1 completed: Lakekeeper connection created'
\prompt 'Press Enter to continue to Step 2 (Create Iceberg source)...' dummy

\echo
\echo '=== Step 2: Create Iceberg source to read historical sales data ==='
CREATE SOURCE historical_sales_iceberg
WITH (
    connector = 'iceberg',
    database.name = 'public',
    table.name = 'sales_history',
    connection = lakekeeper_catalog_conn
);

\echo 'Step 2 completed: Iceberg source created'
\prompt 'Press Enter to continue to Step 3 (Create Kafka source)...' dummy

\echo
\echo '=== Step 3: Create Kafka source for streaming sales data ==='
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
) WITH (
    connector = 'kafka',
    topic = 'sales-stream',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'latest'
) FORMAT PLAIN ENCODE JSON;

\echo 'Step 3 completed: Kafka source created'
\prompt 'Press Enter to continue to Step 4 (Create consolidated table)...' dummy

\echo
\echo '=== Step 4: Create RisingWave table for consolidated sales data ==='
CREATE TABLE sales_consolidated (
    sale_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    product_id INTEGER,
    product_name VARCHAR,
    sale_timestamp TIMESTAMPTZ,
    quantity INTEGER,
    unit_price INTEGER,
    total_price INTEGER,
    currency VARCHAR DEFAULT 'USD',
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER DEFAULT 0,
    data_source VARCHAR, -- 'historical' or 'streaming',
    ingestion_time TIMESTAMPTZ as proctime()
);

\echo 'Step 4 completed: Consolidated table created'
\prompt 'Press Enter to continue to Step 5 (Insert historical data)...' dummy

\echo
\echo '=== Step 5: Insert historical data from Iceberg into the consolidated table ==='
INSERT INTO sales_consolidated (
    sale_id,
    user_id,
    product_id,
    product_name,
    sale_timestamp,
    quantity,
    unit_price,
    total_price,
    currency,
    store_id,
    region,
    payment_method,
    discount_amount,
    data_source
)
SELECT 
    sale_id,
    user_id,
    product_id,
    product_name,
    sale_timestamp,
    quantity,
    unit_price,
    total_price,
    COALESCE(currency, 'USD') as currency,
    store_id,
    region,
    payment_method,
    COALESCE(discount_amount, 0) as discount_amount,
    'historical' as data_source
FROM historical_sales_iceberg;

\echo 'Step 5 completed: Historical data inserted'
\prompt 'Press Enter to verify data ingestion...' dummy

\echo
\echo '=== Verify historical data ingestion ==='
SELECT data_source, COUNT(*) AS record_count 
FROM sales_consolidated 
GROUP BY data_source 
ORDER BY record_count;

\echo
\echo '=== Check recent sales activity ==='
SELECT * FROM sales_consolidated ORDER BY ingestion_time DESC LIMIT 10;

\echo 'Historical data verification completed'
\prompt 'Press Enter to continue to Step 6 (Create streaming sink)...' dummy

\echo
\echo '=== Step 6: Create sink to continuously stream data from Kafka into the same table ==='
CREATE SINK streaming_sales_ingestion INTO sales_consolidated AS
SELECT 
    sale_id,
    user_id,
    product_id,
    product_name,
    sale_timestamp,
    quantity,
    unit_price,
    total_price,
    COALESCE(currency, 'USD') as currency,
    store_id,
    region,
    payment_method,
    COALESCE(discount_amount, 0) as discount_amount,
    'streaming' as data_source
FROM streaming_sales_kafka;

\echo 'Step 6 completed: Streaming sink created'
\prompt 'Press Enter to continue to Step 7 (Create ClickHouse sink)...' dummy

\echo
\echo '=== Step 7: Create sink from RisingWave to ClickHouse for analytics ==='
CREATE SINK sales_to_clickhouse
FROM sales_consolidated
WITH (
    connector = 'clickhouse',
    type = 'upsert',
    clickhouse.url = 'http://clickhouse-server:8123',
    clickhouse.user = 'default',
    clickhouse.password = 'default',
    clickhouse.database = 'default',
    clickhouse.table = 'ck_sales_analytics',
    primary_key = 'sale_id'
);

\echo 'Step 7 completed: ClickHouse sink created'
\prompt 'Press Enter to run final verification queries...' dummy

\echo
\echo '=== Final verification: Check data distribution ==='
SELECT data_source, COUNT(*) AS record_count 
FROM sales_consolidated 
GROUP BY data_source 
ORDER BY record_count;

\echo
\echo '=== Check recent sales activity ==='
SELECT * FROM sales_consolidated ORDER BY ingestion_time DESC LIMIT 10;

\echo 'Final verification completed'
\prompt 'Press Enter to see additional query examples (or Ctrl+C to exit)...' dummy

\echo
\echo '=== Additional Query Examples ==='

\echo
\echo '--- Check total record count ---'
SELECT COUNT(*) as total_records FROM sales_consolidated;

\echo
\echo '--- Check data source distribution ---'
SELECT 
    data_source,
    COUNT(*) as record_count,
    MIN(sale_timestamp) as earliest_sale,
    MAX(sale_timestamp) as latest_sale
FROM sales_consolidated 
GROUP BY data_source;

\echo
\echo '--- Check recent sales activity (detailed) ---'
SELECT 
    sale_id,
    product_name,
    total_price,
    data_source,
    ingestion_time
FROM sales_consolidated 
ORDER BY ingestion_time DESC 
LIMIT 10;

\echo
\echo '--- Sales summary by region and data source ---'
SELECT 
    region,
    data_source,
    COUNT(*) as transaction_count,
    SUM(total_price) as total_revenue,
    AVG(total_price) as avg_transaction_value
FROM sales_consolidated 
GROUP BY region, data_source
ORDER BY total_revenue DESC;

\echo
\echo '======================================='
\echo 'Demo completed successfully!'
\echo 'All data sources are now connected and streaming to ClickHouse'
\echo 'You can watch the query results via'
\echo '  • ./client.sh watch-ck'
\echo '======================================='
-- RisingWave SQL to ingest historical data from Iceberg and stream data from Kafka
-- This example uses a sales table schema to demonstrate the pattern
\set ECHO queries
\pset pager off

\set GREEN '\033[0;32m'
\set YELLOW '\033[1;33m'
\set BLUE '\033[0;34m'
\set NC '\033[0m'

\echo :GREEN
\echo '======================================='
\echo 'RisingWave Demo: Iceberg + Kafka → ClickHouse Table'
\echo
\echo 'Please make sure you have run ./prepare.sh to set up the environment'
\echo
\echo 'You can now run `./client.sh watch-ch` in other panel to watch the clickhouse query results'
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
\prompt 'Press Enter to continue to Step 2 (Create Iceberg source)...' dummy

\echo :GREEN
\echo '=== Step 2: Create Iceberg source to read historical sales data ==='
\echo :BLUE
CREATE SOURCE historical_sales_iceberg
WITH (
    connector = 'iceberg',
    database.name = 'public',
    table.name = 'sales_history',
    connection = lakekeeper_catalog_conn
);

\echo :GREEN
\echo 'Step 2 completed: Iceberg source created'
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
) WITH (
    connector = 'kafka',
    topic = 'sales-stream',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'latest'
) FORMAT PLAIN ENCODE JSON;

\echo :GREEN
\echo 'Step 3 completed: Kafka source created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 4 (Create consolidated table)...' dummy

\echo :GREEN
\echo '=== Step 4: Create RisingWave table for consolidated sales data ==='
\echo :BLUE
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

\echo :GREEN
\echo 'Step 4 completed: Consolidated table created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 5 (Insert historical data)...' dummy

\echo :GREEN
\echo '=== Step 5: Insert historical data from Iceberg into the consolidated table ==='
\echo :BLUE
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

FLUSH;

\echo :GREEN
\echo 'Step 5 completed: Historical data inserted'
\echo :YELLOW
\prompt 'Press Enter to verify data ingestion...' dummy

\echo :GREEN
\echo '=== Verify historical data ingestion ==='
\echo :BLUE
SELECT data_source, COUNT(*) AS record_count 
FROM sales_consolidated 
GROUP BY data_source 
ORDER BY record_count;

\echo :GREEN
\echo '=== Check recent sales activity ==='
\echo :BLUE
SELECT * FROM sales_consolidated ORDER BY ingestion_time DESC LIMIT 10;

\echo :GREEN
\echo 'Historical data verification completed'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 6 (Create streaming sink)...' dummy

\echo :GREEN
\echo '=== Step 6: Create sink to continuously stream data from Kafka into the same table ==='
\echo :BLUE
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

\echo :GREEN
\echo 'Step 6 completed: Streaming sink created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 7 (Create ClickHouse sink)...' dummy

\echo :GREEN
\echo '=== Step 7: Create sink from RisingWave to ClickHouse for analytics ==='
\echo :BLUE
CREATE SINK sales_to_clickhouse
FROM sales_consolidated
WITH (
    connector = 'clickhouse',
    type = 'upsert',
    clickhouse.url = 'http://clickhouse-server:8123',
    clickhouse.user = 'default',
    clickhouse.password = 'default',
    clickhouse.database = 'default',
    clickhouse.table = 'ch_sales_analytics',
    commit_checkpoint_interval = '1',
    primary_key = 'sale_id'
);

\echo :GREEN
\echo 'Step 7 completed: ClickHouse sink created'
\echo :YELLOW
\prompt 'Press Enter to run final verification queries...' dummy

\echo :GREEN
\echo '=== Final verification: Check data distribution ==='
\echo :BLUE
SELECT data_source, COUNT(*) AS record_count 
FROM sales_consolidated 
GROUP BY data_source 
ORDER BY record_count;

\echo :GREEN
\echo '=== Check recent sales activity ==='
\echo :BLUE
SELECT * FROM sales_consolidated ORDER BY ingestion_time DESC LIMIT 10;

\echo :GREEN
\echo 'Final verification completed'
\echo :YELLOW
\prompt 'Press Enter to exit...' dummy

\echo :GREEN
\echo '======================================='
\echo 'Demo completed successfully!'
\echo 'All data sources are now connected and streaming to ClickHouse'
\echo 'You can watch the query results via'
\echo '  • ./client.sh watch-ch'
\echo '  • You will see streaming data_source record'
\echo '    count keeps increasing'
\echo '  • You will see the latest ingested records'
\echo '    with recent ingestion_time keeps changing'
\echo
\echo 'Remember to run ./stop.sh before continuing onto the next demo'
\echo '======================================='
\echo :NC
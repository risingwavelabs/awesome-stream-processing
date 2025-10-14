-- RisingWave SQL for incremental enrichment with CDC, Kafka, deliver to Clickhouse
-- This example demonstrates real-time product enrichment using CDC and streaming data
\set ECHO queries
\pset pager off
\set GREEN '\033[0;32m'
\set YELLOW '\033[1;33m'
\set BLUE '\033[0;34m'
\set NC '\033[0m'

\echo :GREEN
\echo '======================================='
\echo 'RisingWave Demo: Incremental Enrichment'
\echo 'CDC + Kafka → Enriched Data → ClickHouse'
\echo
\echo 'Please make sure you have run ./prepare.sh to set up the environment'
\echo
\echo 'You can now run `./client.sh watch-ch` in other panel to watch the clickhouse query results'
\echo '======================================='
\echo :YELLOW
\prompt 'Press Enter to start Step 1 (Create PostgreSQL CDC source)...' dummy

\echo :GREEN
\echo '=== Step 1: Create PostgreSQL CDC source for product data ==='
\echo :BLUE
CREATE SOURCE pg_cdc_source WITH (
    connector='postgres-cdc',
    hostname='oltp',
    port='5432',
    username='myuser',
    password='123456',
    database.name='mydb',
);

\echo :GREEN
\echo 'Step 1 completed: PostgreSQL CDC source created'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 2 (Create CDC table)...' dummy

\echo :GREEN
\echo '=== Step 2: Create CDC table from OLTP Postgres product table ==='
\echo :BLUE
CREATE TABLE streaming_product_pg (*)
FROM pg_cdc_source TABLE 'public.product';

\echo :GREEN
\echo 'Step 2 completed: CDC table created for product data'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 3 (Create Kafka source)...' dummy

\echo :GREEN
\echo '=== Step 3: Create Kafka source for streaming sales data ==='
\echo :BLUE
CREATE SOURCE streaming_sales_kafka (
    sale_id INTEGER,
    product_id INTEGER,
    sale_timestamp TIMESTAMPTZ,
    quantity INTEGER,
    total_price INTEGER,
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
\echo 'Step 3 completed: Kafka source created for sales stream'
\echo :YELLOW
\prompt 'Press Enter to continue to Step 4 (Incremental enrichment and sink to clickhouse)...' dummy

\echo :GREEN
\echo '=== Step 4: Incremental enrichment and create direct sink to ClickHouse for analytics ==='
\echo :BLUE
CREATE SINK enriched_sales_to_clickhouse AS
SELECT 
    sale_id,
    s.product_id as product_id,
    product_name,
    category,
    list_price as unit_price,
    currency,
    sale_timestamp,
    quantity,
    total_price,
    store_id,
    region,
    payment_method,
    discount_amount,
    active,
    p.updated_at as product_last_updated,
    s.ingestion_time as kafka_ingestion_time
FROM streaming_sales_kafka s
LEFT JOIN streaming_product_pg p ON s.product_id = p.product_id
WITH (
    connector = 'clickhouse',
    type = 'upsert',
    clickhouse.url = 'http://clickhouse-server:8123',
    clickhouse.user = 'default',
    clickhouse.password = 'default',
    clickhouse.database = 'default',
    clickhouse.table = 'ch_enriched_sales_analytics',
    commit_checkpoint_interval = '1',
    primary_key = 'sale_id'
);

\echo :GREEN
\echo 'Step 4 completed: ClickHouse sink created'
\echo :YELLOW
\prompt 'Press Enter to exit...' dummy


\echo :GREEN
\echo '======================================='
\echo 'Demo completed successfully!'
\echo 'Real-time sales enrichment pipeline is active:'
\echo '• Product data flows via PostgreSQL CDC'
\echo '• Sales data streams from Kafka'  
\echo '• Enriched data streams directly to ClickHouse'
\echo '• You can watch the query results via'
\echo '  • ./client.sh watch-ch'
\echo
\echo 'Remember to run ./stop.sh before continuing onto the next demo'
\echo '======================================='
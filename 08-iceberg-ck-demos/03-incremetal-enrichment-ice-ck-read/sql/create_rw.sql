-- RisingWave SQL for incremental enrichment with CDC, Kafka, and Iceberg
-- This example demonstrates real-time product enrichment using CDC and streaming data
\set ECHO queries
\pset pager off

\echo
\echo '======================================='
\echo 'RisingWave Demo: Incremental Enrichment'
\echo 'CDC + Kafka → Enriched Iceberg → ClickHouse Query'
\echo '======================================='
\echo
\prompt 'Press Enter to start Step 1 (Create PostgreSQL CDC source)...' dummy

\echo
\echo '=== Step 1: Create PostgreSQL CDC source for product data ==='
CREATE SOURCE pg_cdc_source WITH (
    connector='postgres-cdc',
    hostname='oltp',
    port='5432',
    username='myuser',
    password='123456',
    database.name='mydb',
);

\echo 'Step 1 completed: PostgreSQL CDC source created'
\prompt 'Press Enter to continue to Step 2 (Create CDC table)...' dummy

\echo
\echo '=== Step 2: Create CDC table from OLTP Postgres product table ==='
CREATE TABLE streaming_product_pg (*)
FROM pg_cdc_source TABLE 'public.product';

\echo 'Step 2 completed: CDC table created for product data'
\prompt 'Press Enter to continue to Step 3 (Create Kafka source)...' dummy

\echo
\echo '=== Step 3: Create Kafka source for streaming sales data ==='
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

\echo 'Step 3 completed: Kafka source created for sales stream'
\prompt 'Press Enter to continue to Step 4 (Create Lakekeeper connection)...' dummy

\echo
\echo '=== Step 4: Create connection to Lakekeeper catalog for Iceberg access ==='
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

\echo 'Step 4 completed: Lakekeeper connection created'
\prompt 'Press Enter to continue to Step 5 (Set Iceberg engine connection)...' dummy

\echo
\echo '=== Step 5: Set Iceberg engine connection ==='
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';

\echo 'Step 5 completed: Iceberg engine connection set'
\prompt 'Press Enter to continue to Step 6 (Create enriched Iceberg table)...' dummy

\echo
\echo '=== Step 6: Create Iceberg table for enriched sales data ==='
CREATE TABLE enriched_sales_iceberg (
    sale_id INTEGER PRIMARY KEY,
    product_id INTEGER,
    product_name VARCHAR,
    category VARCHAR,
    unit_price INTEGER,
    currency VARCHAR,
    sale_timestamp TIMESTAMP,
    quantity INTEGER,
    total_price INTEGER,
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER,
    active BOOLEAN,
    product_last_updated TIMESTAMP,
    kafka_ingestion_time TIMESTAMP
) WITH (
    commit_checkpoint_interval = 1,
    compaction_interval_sec = 5,
    snapshot_expiration_max_age_millis = 0,
    write_mode = 'copy-on-write',
)
ENGINE = iceberg;

\echo 'Step 6 completed: Enriched Iceberg table created'
\prompt 'Press Enter to continue to Step 7 (Create enrichment sink)...' dummy

\echo
\echo '=== Step 7: Create sink to persist enriched sales data in Iceberg ==='
CREATE SINK enriched_sales INTO enriched_sales_iceberg AS
SELECT 
    sale_id,
    s.product_id as product_id,
    product_name,
    category,
    list_price as unit_price,
    currency,
    sale_timestamp::timestamp,
    quantity,
    total_price,
    store_id,
    region,
    payment_method,
    discount_amount,
    active,
    p.updated_at::timestamp as product_last_updated,
    s.ingestion_time::timestamp as kafka_ingestion_time
FROM streaming_sales_kafka s
LEFT JOIN streaming_product_pg p ON s.product_id = p.product_id;

\echo 'Step 7 completed: Enrichment sink created'
\echo 'Sales data will now be enriched with product information from CDC'
\prompt 'Press Enter to verify data ingestion and enrichment...' dummy

\echo
\echo '=== Verify enriched data ingestion ==='
SELECT COUNT(*) AS record_count 
FROM enriched_sales_iceberg;

\echo
\echo '=== Check recent enriched sales activity ==='
SELECT * FROM enriched_sales_iceberg ORDER BY kafka_ingestion_time DESC,product_last_updated DESC LIMIT 10;

\echo 'Data verification completed'
\echo
\echo '======================================='
\echo 'Demo completed successfully!'
\echo 'Real-time sales enrichment pipeline is active:'
\echo '• Product data flows via PostgreSQL CDC'
\echo '• Sales data streams from Kafka'  
\echo '• Enriched data persists in Iceberg'
\echo '• Ready for ClickHouse analytics'
\echo '• You can watch the query results via'
\echo '  • ./client.sh watch-ck'
\echo '  • ./client.sh watch-rw'
\echo '======================================='
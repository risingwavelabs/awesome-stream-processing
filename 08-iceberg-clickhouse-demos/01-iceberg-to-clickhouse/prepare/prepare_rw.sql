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

CREATE SOURCE iceberg_source
WITH (
    connector = 'iceberg',
    database.name = 'public',
    table.name = 'sales_history',
    connection = lakekeeper_catalog_conn
);

CREATE TABLE sales (
    sale_id INTEGER PRIMARY KEY,
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
    discount_amount INTEGER,
    ingestion_time TIMESTAMPTZ as proctime()
);


CREATE SINK sales_cdc INTO sales
FROM iceberg_source;


CREATE SINK sales_to_clickhouse
FROM sales
WITH (
    connector = 'clickhouse',
    type = 'upsert',
    clickhouse.url = 'http://clickhouse-server:8123',
    clickhouse.user = 'default',
    clickhouse.password = 'default',
    clickhouse.database = 'default',
    clickhouse.table = 'ch_sales',
    commit_checkpoint_interval = '1',
    primary_key = 'sale_id'
);
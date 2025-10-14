-- Create table for enriched sales analytics data from RisingWave
CREATE TABLE IF NOT EXISTS ch_enriched_sales_analytics (
    sale_id Int32,
    product_id Int32,
    product_name String,
    category String,
    unit_price Int32,
    currency String,
    sale_timestamp DateTime64(3),
    quantity Int32,
    total_price Int32,
    store_id Int32,
    region String,
    payment_method String,
    discount_amount Int32,
    active Bool,
    product_last_updated DateTime64(3),
    kafka_ingestion_time DateTime64(3),
    Sign Int8
) ENGINE = CollapsingMergeTree(Sign)
ORDER BY (sale_id);
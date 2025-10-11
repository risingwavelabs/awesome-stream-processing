CREATE TABLE ck_sales_analytics (
    sale_id Int32,
    user_id Int32,
    product_id Int32,
    product_name String,
    sale_timestamp DateTime64(3),
    quantity Int32,
    unit_price Int32,
    total_price Int32,
    currency String,
    store_id Int32,
    region String,
    payment_method String,
    discount_amount Int32,
    data_source String,
    ingestion_time DateTime64(3),
    Sign Int8
) ENGINE = CollapsingMergeTree(Sign)
ORDER BY (sale_id);
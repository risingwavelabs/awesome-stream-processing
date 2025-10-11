/* 
    Populate sample data to iceberg.
    In the demo, we use RW to populate sample data to Iceberg just for convenience.
    You can use other Iceberg writer to populate sample data as well.
*/

-- Create connection to Lakekeeper catalog for Iceberg access
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

SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';

-- Step 1: Create Iceberg table for historical sales data and populate with examples
CREATE TABLE IF NOT EXISTS sales_history (
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
    discount_amount INTEGER
)
WITH (
    commit_checkpoint_interval = 1,
    compaction_interval_sec = 5,
    snapshot_expiration_max_age_millis = 0,
    write_mode = 'copy-on-write',
)
ENGINE = iceberg;

-- Step 2: Populate sales_history with example historical data
INSERT INTO sales_history (
    sale_id, user_id, product_id, product_name, sale_timestamp,
    quantity, unit_price, total_price, currency, store_id, region, payment_method, discount_amount
) VALUES
(1001, 101, 201, 'iPhone 15 Pro', '2024-01-15 10:30:00', 1, 999, 999, 'USD', 1, 'North America', 'Credit Card', 0),
(1002, 102, 202, 'MacBook Air M3', '2024-01-15 11:45:00', 1, 1299, 1169, 'USD', 1, 'North America', 'Debit Card', 129),
(1003, 103, 203, 'AirPods Pro', '2024-01-16 09:15:00', 2, 249, 498, 'USD', 2, 'Europe', 'PayPal', 0),
(1004, 104, 204, 'iPad Pro 12.9', '2024-01-16 14:20:00', 1, 1099, 1044, 'USD', 3, 'Asia Pacific', 'Credit Card', 54),
(1005, 105, 205, 'Apple Watch Series 9', '2024-01-17 16:30:00', 1, 399, 379, 'USD', 1, 'North America', 'Apple Pay', 19),
(1006, 106, 201, 'iPhone 15 Pro', '2024-01-17 13:45:00', 1, 999, 899, 'USD', 2, 'Europe', 'Credit Card', 99),
(1007, 107, 206, 'Mac Studio M2', '2024-01-18 10:00:00', 1, 1999, 1999, 'USD', 4, 'North America', 'Wire Transfer', 0),
(1008, 108, 207, 'Magic Keyboard', '2024-01-18 15:15:00', 3, 129, 387, 'USD', 2, 'Europe', 'Credit Card', 0),
(1009, 109, 208, 'Magic Mouse', '2024-01-19 11:30:00', 2, 79, 142, 'USD', 3, 'Asia Pacific', 'Debit Card', 15),
(1010, 110, 209, 'Apple TV 4K', '2024-01-19 17:45:00', 1, 179, 161, 'USD', 1, 'North America', 'Apple Pay', 17),
(1011, 111, 210, 'HomePod mini', '2024-01-20 12:00:00', 2, 99, 188, 'USD', 4, 'Europe', 'PayPal', 9),
(1012, 112, 202, 'MacBook Air M3', '2024-01-20 14:30:00', 1, 1299, 1234, 'USD', 3, 'Asia Pacific', 'Credit Card', 64),
(1013, 113, 211, 'AirTag 4-pack', '2024-01-21 09:45:00', 1, 99, 94, 'USD', 1, 'North America', 'Debit Card', 4),
(1014, 114, 212, 'iPhone 15', '2024-01-21 16:15:00', 1, 799, 719, 'USD', 2, 'Europe', 'Credit Card', 79),
(1015, 115, 213, 'iPad Air', '2024-01-22 13:20:00', 1, 599, 569, 'USD', 4, 'Asia Pacific', 'Apple Pay', 29);

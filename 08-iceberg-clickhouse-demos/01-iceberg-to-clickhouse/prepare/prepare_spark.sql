-- Spark SQL script to create sales_history table in Iceberg with Copy-on-Write mode
-- This allows efficient INSERT, UPDATE, and DELETE operations

-- Create a namespace (database) if it doesn't exist
CREATE NAMESPACE IF NOT EXISTS lake.public;

-- Use the namespace
USE lake.public;

-- Create the sales_history table with Copy-on-Write mode
CREATE TABLE IF NOT EXISTS sales_history (
    sale_id INT,
    user_id INT,
    product_id INT,
    product_name STRING,
    sale_timestamp TIMESTAMP,
    quantity INT,
    unit_price INT,
    total_price INT,
    currency STRING,
    store_id INT,
    region STRING,
    payment_method STRING,
    discount_amount INT
) USING iceberg
TBLPROPERTIES (
    'write.format.default' = 'parquet',
    'write.delete.mode' = 'copy-on-write',
    'write.update.mode' = 'copy-on-write',
    'write.merge.mode' = 'copy-on-write',
    'format-version' = '2'
);

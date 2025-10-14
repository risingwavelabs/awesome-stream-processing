/* 
    Populate sample data to Kafka topic.
    In the demo, we use RW to populate sample data to Kafka just for convenience.
    You can use other Kafka producer to populate sample data as well.
*/

-- This script creates a Kafka sink and uses datagen to produce example sales data
CREATE SCHEMA IF NOT EXISTS data_gen;

-- Step 1: Create a datagen source with fixed product catalog
CREATE SOURCE IF NOT EXISTS data_gen.sales_stream (
    sale_id INTEGER,
    product_id INTEGER,
    sale_timestamp TIMESTAMPTZ,
    quantity INTEGER,
    total_price INTEGER,
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER
) WITH (
    connector = 'datagen',
    fields.sale_id.kind = 'sequence',
    fields.sale_id.start = '2000',
    fields.sale_id.end = '99999',

    fields.product_id.kind = 'random',
    fields.product_id.min = '301',
    fields.product_id.max = '320',

    fields.sale_timestamp.kind = 'random',
    fields.sale_timestamp.max_past = '0 days',
    fields.sale_timestamp.max_future = '1 days',

    fields.quantity.kind = 'random',
    fields.quantity.min = '1',
    fields.quantity.max = '3',

    fields.store_id.kind = 'random',
    fields.store_id.min = '1',
    fields.store_id.max = '5',

    fields.discount_amount.kind = 'random',
    fields.discount_amount.min = '0',
    fields.discount_amount.max = '99',

    datagen.rows.per.second = '1'
) FORMAT PLAIN ENCODE JSON;

-- Step 2: Create Kafka sink to send enriched sales data to sales-stream topic
CREATE SINK IF NOT EXISTS data_gen.sales_stream_sink AS 
SELECT 
    sale_id,
    product_id,
    sale_timestamp,
    quantity,
    -- total_price is just a placeholder here; will be enriched downstream
    total_price,
    store_id,
    region,
    payment_method,
    discount_amount
FROM data_gen.sales_stream
WITH (
    connector = 'kafka',
    topic = 'sales-stream',
    properties.bootstrap.server = 'message_queue:29092',
) FORMAT PLAIN ENCODE JSON;

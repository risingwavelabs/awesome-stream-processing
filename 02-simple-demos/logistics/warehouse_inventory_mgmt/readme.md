# Inventory management and demand forecast

Track inventory levels and forecast demand to prevent shortages and optimize restocking schedules.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the official documentation.

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following two queries to set up your tables in RisingWave.

```sql
CREATE TABLE inventory (
    warehouse_id INT,
    product_id INT,
    timestamp TIMESTAMPTZ,
    stock_level INT,
    reorder_point INT,
    location VARCHAR
);
```

```sql
CREATE TABLE sales (
    sale_id INT,
    warehouse_id INT,
    product_id INT,
    quantity_sold INT,
    timestamp TIMESTAMPTZ
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the [data generator](02-simple-demos/logistics/warehouse_inventory_mgmt/data_generator.py).

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW inventory_status AS
SELECT
    warehouse_id,
    product_id,
    stock_level,
    reorder_point,
    location,
    CASE
        WHEN stock_level <= reorder_point THEN 'Reorder Needed'
        ELSE 'Stock Sufficient'
    END AS reorder_status,
    timestamp AS last_update
FROM
    inventory;

```

```sql
CREATE MATERIALIZED VIEW recent_sales AS
SELECT
    warehouse_id,
    product_id,
    SUM(quantity_sold) AS total_quantity_sold,
    MAX(timestamp) AS last_sale
FROM
    sales
WHERE
    timestamp > NOW() - INTERVAL '7 days'
GROUP BY
    warehouse_id, product_id;
```

```sql
CREATE MATERIALIZED VIEW demand_forecast AS
SELECT
    i.warehouse_id,
    i.product_id,
    i.stock_level,
    r.total_quantity_sold AS weekly_sales,
    CASE
        WHEN r.total_quantity_sold = 0 THEN 0
        ELSE ROUND(i.stock_level / r.total_quantity_sold, 2)
    END AS stock_days_remaining
FROM
    inventory_status AS i
LEFT JOIN
    recent_sales AS r
ON
    i.warehouse_id = r.warehouse_id AND i.product_id = r.product_id;
```
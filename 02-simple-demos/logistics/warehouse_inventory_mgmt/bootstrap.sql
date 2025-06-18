CREATE TABLE inventory (
    warehouse_id INT,
    product_id INT,
    timestamp TIMESTAMPTZ,
    stock_level INT,
    reorder_point INT,
    location VARCHAR
);

CREATE TABLE sales (
    sale_id INT,
    warehouse_id INT,
    product_id INT,
    quantity_sold INT,
    timestamp TIMESTAMPTZ
);

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
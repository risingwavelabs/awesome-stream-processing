## Create materialized views

Run each of the following queries to start monitoring the energy usage patterns and monthly bills of each household. 

In order to properly load the Grafana dashboard, all materialized views must be created.

### Track stock - categorize as low/high stock

```sql
CREATE MATERIALIZED VIEW product_stock_status AS
WITH inventory_updates AS (
    SELECT 
        b.product_id,
        b.product_name,
        b.base_price,
        iu.window_start,
        b.reorder_threshold,
        SUM(COALESCE(iu.total_restocked, 0)) OVER (PARTITION BY b.product_id ORDER BY iu.window_start) - 
        SUM(COALESCE(iu.total_purchased, 0)) OVER (PARTITION BY b.product_id ORDER BY iu.window_start) + 
        b.stock_level AS current_inventory
    FROM 
        product_inventory b
    LEFT JOIN (
        SELECT 
            COALESCE(p.product_id, r.product_id) AS product_id,
            COALESCE(p.window_start, r.window_start) AS window_start,
            COALESCE(p.total_purchased, 0) AS total_purchased,
            COALESCE(r.total_restocked, 0) AS total_restocked
        FROM 
            (SELECT 
                 product_id,
                 window_start,
                 SUM(quantity_purchased) AS total_purchased
             FROM 
                 TUMBLE(purchases, purchase_time, '1 MINUTE')
             GROUP BY 
                 product_id, window_start
            ) p
        FULL JOIN 
            (SELECT 
                 product_id,
                 window_start,
                 SUM(quantity_restocked) AS total_restocked
             FROM 
                 TUMBLE(restocks, restock_time, '1 MINUTE')  
             GROUP BY 
                 product_id, window_start
            ) r
        ON 
            p.product_id = r.product_id AND p.window_start = r.window_start
    ) iu 
    ON b.product_id = iu.product_id
)
SELECT 
    product_id,
    product_name,
    window_start AS inventory_window,
    current_inventory,
    base_price,
    reorder_threshold,
    CASE 
        WHEN current_inventory < 20 THEN 'Low'
        WHEN current_inventory BETWEEN 20 AND 50 THEN 'Medium'
        ELSE 'High'
    END AS stock_level_category
FROM 
    inventory_updates;
```
### Create pricing model, add new column for listing price

If stock is low and demand is high, increase sale price by 20%. If stock is high and demand is low, decrease sale price by 10%.

```sql
CREATE MATERIALIZED VIEW dynamic_pricing_mv AS
SELECT 
    product_id,
    product_name,
    inventory_window,
    current_inventory,
    stock_level_category,
    base_price,
    CASE 
        WHEN stock_level_category = 'Low' THEN ROUND(base_price * 1.20, 2)  
        WHEN stock_level_category = 'Medium' THEN base_price              
        WHEN stock_level_category = 'High' THEN ROUND(base_price * 0.90, 2) 
    END AS new_price
FROM 
    product_stock_status;
```
### Track sales

```sql
CREATE MATERIALIZED VIEW sales_profit AS
SELECT 
    p.product_id,
    dpm.product_name,
    SUM(p.quantity_purchased) AS total_purchased,
    SUM(dpm.new_price * p.quantity_purchased) AS total_profit
FROM 
    purchases p
ASOF LEFT JOIN 
    dynamic_pricing_mv dpm
ON 
    p.product_id = dpm.product_id 
    AND p.purchase_time >= dpm.inventory_window
GROUP BY product_id, product_name;
```

### Find products with excess inventory

```sql
CREATE MATERIALIZED VIEW excess_inventory AS
WITH daily_inventory AS (
    SELECT 
        product_id,
        product_name,
        window_start,
        SUM(current_inventory) AS total_inventory,
        AVG(reorder_threshold) AS reorder_level
    FROM 
        TUMBLE(product_stock_status, inventory_window, '5 MINUTES')
    GROUP BY 
        product_id, product_name, window_start
)
SELECT 
    product_id,
    product_name,
    window_start,
    total_inventory AS current_inventory,
    reorder_level,
    CASE 
        WHEN total_inventory > reorder_level * 1.5 THEN 'Excess'
        ELSE 'Normal'
    END AS inventory_status
FROM 
    daily_inventory;
```

### Analyze how sales change with varying prices

```sql
CREATE MATERIALIZED VIEW demand_elasticity AS
WITH sales_with_prices AS (
    SELECT 
        ps.product_id,
        ps.product_name,
        dp.new_price AS price_at_purchase,
        SUM(p.quantity_purchased) AS total_quantity_sold,
        SUM(p.quantity_purchased * dp.new_price) AS total_revenue
    FROM 
        purchases p
    ASOF JOIN 
        dynamic_pricing_mv dp
    ON 
        p.product_id = dp.product_id 
        AND p.purchase_time >= dp.inventory_window
    JOIN 
        product_stock_status ps
    ON 
        p.product_id = ps.product_id
    GROUP BY 
        ps.product_id, ps.product_name, dp.new_price
)
SELECT 
		product_id,
		product_name,
    price_at_purchase AS price_range,
    SUM(total_quantity_sold) AS total_quantity,
    SUM(total_revenue) AS total_revenue,
    AVG(total_quantity_sold) AS avg_quantity_sold
FROM 
    sales_with_prices
GROUP BY 
    price_at_purchase, product_id, product_name
ORDER BY 
    price_range;
```
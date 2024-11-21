-- This MV calculates aggregated sales data for products within 1-minute intervals and select specific columns from the result for analysis or reporting, you can use the following query. It utilizes a Common Table Expression (CTE) named product_sales to perform the calculations and retrieve the desired columns
CREATE MATERIALIZED  VIEW product_sales_summary_by_minute AS
WITH product_sales AS (
    SELECT
        window_start,
        window_end,
        s.sale_id,
        p.product_id,
        SUM(s.total_price) AS total_sales,
        AVG(s.total_price) AS average_revenue_per_sale
    FROM
        TUMBLE (sales, sale_timestamp, INTERVAL '1 MINUTES') as s
    JOIN
        products p ON s.product_id = p.product_id
    GROUP BY
        s.sale_id,
        p.product_id,
        s.window_start,
        s.window_end
)
SELECT
    ps.sale_id,
    ps.product_id,
    ps.total_sales,
    ps.average_revenue_per_sale,
    ps.window_start,
    ps.window_end
FROM
    product_sales ps;
    

-- This MV calculates the count of distinct active users within 1-minute intervals based on their last login times, you can use the following query. It utilizes the TUMBLE function to define the time windows and groups the results by user ID, window start, and window end to compute the total active users in each interval
CREATE MATERIALIZED VIEW active_users_per_minute AS
SELECT
    COUNT(DISTINCT user_id) AS total_active_users,
    window_start,
    window_end
FROM 
     TUMBLE (users, last_login, INTERVAL '1 MINUTES')
GROUP BY
    user_id,
    window_start,
    window_end;

-- This MV retrieves the top 5 products by total quantity sold within 1-minute intervals, you can use the following query. It utilizes the TUMBLE function to define the time windows based on sale timestamps and joins the sales and products tables to gather data about product categories, names, and quantities sold. The results are then grouped by category, product name, window start, and window end. The query is sorted in descending order by total quantity sold and limited to the top 5 products
CREATE MATERIALIZED VIEW top_products_sold_per_minute AS
SELECT
    p.category,
    p.product_name,
    SUM(s.quantity) AS total_quantity_sold,
    window_start,
    window_end
FROM
    TUMBLE (sales, sale_timestamp, INTERVAL '1 MINUTES') as s
JOIN
    products p
ON
    s.product_id = p.product_id
GROUP BY
    p.category, p.product_name, 
    window_start,
    window_end
ORDER BY
    total_quantity_sold DESC
LIMIT
    5;

-- This MV calculates the top 10 users by their total spending within 1-minute intervals, you can use the following query. This query utilizes the TUMBLE function to define the time windows based on user login times. It joins the users and sales tables to gather user information and sales data. The results are then grouped by user ID, username, email, window start, and window end. The query is sorted in descending order by total spending and limited to the top 10 users
CREATE MATERIALIZED VIEW top_spending_users_per_minute AS
SELECT
        u.user_id,
        u.username,
        u.email,
        SUM(s.total_price) AS total_spent,
        window_start,
        window_end
    FROM
        TUMBLE (users, last_login, INTERVAL '1 MINUTES') as u
    JOIN
        sales s
    ON
        u.user_id = s.user_id
    GROUP BY
        u.user_id,
        u.username,
        u.email,
        window_start,
        window_end
    ORDER BY
    total_spent DESC
LIMIT
    10;            

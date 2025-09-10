DROP MATERIALIZED VIEW IF EXISTS customer_segmentation;
DROP MATERIALIZED VIEW IF EXISTS behavior_scores;
DROP MATERIALIZED VIEW IF EXISTS rfm_scores;

DROP MATERIALIZED VIEW IF EXISTS click_behavior_stats;
DROP MATERIALIZED VIEW IF EXISTS order_behavior_stats;
DROP MATERIALIZED VIEW IF EXISTS order_stats;
DROP MATERIALIZED VIEW IF EXISTS global_order_stats;

DROP SOURCE IF EXISTS event_stream;
DROP SOURCE IF EXISTS order_stream;

-- User behavior source
CREATE SOURCE event_stream (
    user_id VARCHAR,
    event_id VARCHAR,
    event_type VARCHAR,
    product_id VARCHAR,
    product_name VARCHAR,
    price DOUBLE PRECISION,
    event_time TIMESTAMP,
    page_url VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'click-stream',
    properties.bootstrap.server = 'localhost:9092'
) FORMAT PLAIN ENCODE JSON;

-- Orders source
CREATE SOURCE order_stream (
    order_id VARCHAR,
    user_id VARCHAR,
    event_id VARCHAR,
    order_status VARCHAR,
    price DOUBLE PRECISION,
    order_time TIMESTAMP,
) WITH (
    connector = 'kafka',
    topic = 'order-stream',
    properties.bootstrap.server = 'localhost:9092'
) FORMAT PLAIN ENCODE JSON;

SET TIME ZONE 'Asia/Shanghai';

-- Calculate user behavior statistics
CREATE MATERIALIZED VIEW click_behavior_stats AS
SELECT
    user_id,
    COUNT(*) FILTER (WHERE event_type = 'view') AS view_count,
    COUNT(*) FILTER (WHERE event_type = 'cart') AS cart_count,
    COUNT(*) FILTER (WHERE event_type = 'purchase') AS purchase_count
FROM event_stream
WHERE event_time >= CURRENT_TIMESTAMP - INTERVAL '2 months'
GROUP BY user_id;

-- Calculate order status statistics
CREATE MATERIALIZED VIEW user_order_stats AS
SELECT
    1 AS id,
    user_id,
    COUNT(*) FILTER (WHERE order_status = 'completed') AS completed_orders,
    SUM(price) AS total_spent,
    MAX(order_time) AS last_order_time
FROM order_stream
GROUP BY user_id;

-- Calculate global max order time
CREATE MATERIALIZED VIEW global_order_stats AS
SELECT
    1 AS id,
    MAX(order_time) AS max_order_time
FROM order_stream;

CREATE MATERIALIZED VIEW order_behavior_stats AS
SELECT
    u.user_id AS user_id,
    u.completed_orders AS completed_orders,
    u.total_spent AS total_spent,
    u.last_order_time AS last_order_time,
    g.max_order_time AS max_order_time
FROM user_order_stats u
JOIN global_order_stats g
ON u.id = g.id;

-- calculate rfm score and behavior score
CREATE MATERIALIZED VIEW rfm_scores AS
SELECT
    user_id,
    -- Recency Score: Recent purchases get higher scores
    CASE
    WHEN max_order_time - last_order_time <= INTERVAL '3 days' THEN 5
    WHEN max_order_time - last_order_time <= INTERVAL '10 days' THEN 4
    WHEN max_order_time - last_order_time <= INTERVAL '30 days' THEN 3
    WHEN max_order_time - last_order_time <= INTERVAL '60 days' THEN 2
    ELSE 1
END AS r_score,
    -- Frequency Score: Higher purchase frequency gets higher scores
    CASE
        WHEN completed_orders >= 15 THEN 5
        WHEN completed_orders >= 8 THEN 4
        WHEN completed_orders >= 5 THEN 3
        WHEN completed_orders >= 2 THEN 2
        ELSE 1
END AS f_score,
    -- Monetary Score: Higher spending gets higher scores
    CASE
        WHEN total_spent >= 5000 THEN 5
        WHEN total_spent >= 2500 THEN 4
        WHEN total_spent >= 1000 THEN 3
        WHEN total_spent >= 200 THEN 2
        ELSE 1
END AS m_score
FROM order_behavior_stats;

CREATE MATERIALIZED VIEW behavior_scores AS
SELECT
    u.user_id,
    -- Browsing Activity Score
    CASE
        WHEN view_count >= 30 THEN 5
        WHEN view_count >= 15 THEN 4
        WHEN view_count >= 8 THEN 3
        WHEN view_count >= 2 THEN 2
        ELSE 1
        END AS browse_score,
    -- Purchase Intent Score
    CASE
        WHEN cart_count >= 10 THEN 5
        WHEN cart_count >= 7 THEN 4
        WHEN cart_count >= 4 THEN 3
        WHEN cart_count >= 2 THEN 2
        ELSE 1
        END AS intent_score
FROM click_behavior_stats u;

-- customer segmentation
CREATE MATERIALIZED VIEW customer_segmentation AS
SELECT
    b.user_id,
    b.browse_score AS browse_score,
    b.intent_score AS intent_score,
    COALESCE(r.r_score, 1) AS r_score,
    COALESCE(r.f_score, 1) AS f_score,
    COALESCE(r.m_score, 1) AS m_score,
    CASE
        -- High-value active customers (high RFM + high activity)
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            AND browse_score >= 3 THEN 'ACTIVE'
        -- New customers (first purchase within 7 days)
        WHEN r_score >= 4 AND f_score = 1 THEN 'NEW'
        -- High-potential customers (high browse/cart but no purchase)
        WHEN browse_score >= 4 AND intent_score >= 3 AND COALESCE(r_score, 1) <= 2 THEN 'HIGH_POTENTIAL'
        -- Dormant high-value customers (low activity but high historical value)
        WHEN COALESCE(r_score, 1) <= 2 AND m_score >= 4 THEN 'DORMANT_HIGH_VALUE'
        -- Average active customers
        WHEN r_score >= 2 AND f_score >= 2 AND m_score >= 2 THEN 'AVERAGE_ACTIVE'
        -- Churned customers
        WHEN COALESCE(r_score, 1) <= 2 AND COALESCE(f_score, 1) <= 2 THEN 'CHURNED'
        ELSE 'OTHER'
        END AS segment
FROM behavior_scores b
LEFT JOIN rfm_scores r
ON r.user_id = b.user_id;

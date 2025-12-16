{{ config(materialized='materialized_view') }}

WITH stats AS (
    SELECT
        -- Create 1-minute tumbling windows
        window_start,
        window_end,
        count(distinct p.user_id) as viewers,
        count(distinct c.user_id) as carters,
        count(distinct pur.user_id) as purchasers
    FROM TUMBLE({{ ref('src_page') }}, event_time, INTERVAL '1 MINUTE') p
    -- Join Cart events
    LEFT JOIN {{ ref('src_cart') }} c 
        ON p.user_id = c.user_id 
        AND c.event_time BETWEEN p.window_start AND p.window_end
    -- Join Purchase events
    LEFT JOIN {{ ref('src_purchase') }} pur 
        ON p.user_id = pur.user_id 
        AND pur.event_time BETWEEN p.window_start AND p.window_end
    GROUP BY window_start, window_end
)

SELECT
    window_start,
    viewers,
    carters,
    purchasers,
    -- Calculate live conversion rates
    case when viewers > 0 then round(carters::numeric / viewers, 2) else 0 end as view_to_cart_rate,
    case when carters > 0 then round(purchasers::numeric / carters, 2) else 0 end as cart_to_buy_rate
FROM stats
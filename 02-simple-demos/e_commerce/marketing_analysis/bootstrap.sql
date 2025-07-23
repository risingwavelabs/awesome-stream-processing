
CREATE SOURCE marketing_events (
  event_id       VARCHAR,
  user_id        INT,
  campaign_id    VARCHAR,
  channel_type   VARCHAR,
  event_type     VARCHAR,
  amount         NUMERIC,
  utm_source     VARCHAR,
  utm_medium     VARCHAR,
  utm_campaign   VARCHAR,
  timestamp      TIMESTAMPTZ
) WITH (
  connector                   = 'kafka',
  topic                       = 'marketing_events',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE campaigns (
    campaign_id varchar,
    campaign_name varchar,
    campaign_type varchar,  
    start_date timestamptz,
    end_date timestamptz,
    budget numeric,
    target_audience varchar
) WITH (
  connector                   = 'kafka',
  topic                       = 'campaigns',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE ab_test_variants (
    variant_id varchar,
    campaign_id varchar,
    variant_name varchar, 
    variant_type varchar,  
    content_details varchar
) WITH (
  connector = 'kafka',
  topic = 'ab_test_variants',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE MATERIALIZED VIEW campaign_performance AS
SELECT
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,
    COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END) as impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END) as clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END), 0) as ctr,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END), 0) as conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '1 HOUR')
JOIN campaigns c ON me.campaign_id = c.campaign_id
GROUP BY
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    c.campaign_type;

CREATE MATERIALIZED VIEW channel_attribution AS
SELECT
    window_start,
    window_end,
    channel_type,
    utm_source,
    utm_medium,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END), 0) as avg_order_value
FROM TUMBLE(marketing_events, timestamp, INTERVAL '1 HOUR')
GROUP BY
    window_start,
    window_end,
    channel_type,
    utm_source,
    utm_medium;

CREATE MATERIALIZED VIEW ab_test_results AS
SELECT
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    av.variant_name,
    av.variant_type,
    COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END) as impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END) as clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END), 0) as conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '1 HOUR')
JOIN campaigns c ON me.campaign_id = c.campaign_id
JOIN ab_test_variants av ON c.campaign_id = av.campaign_id
WHERE c.campaign_type = 'ab_test'
GROUP BY
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    av.variant_name,
    av.variant_type;

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
  variant_id     VARCHAR,
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
  COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END) AS impressions,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END) AS clicks,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END), 0) AS ctr,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END), 0) AS conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
JOIN campaigns c ON marketing_events.campaign_id = c.campaign_id
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
  COUNT(DISTINCT user_id) AS unique_users,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END), 0) AS avg_order_value
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
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
  COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END) AS impressions,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END) AS clicks,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END), 0) AS conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
JOIN campaigns c ON marketing_events.campaign_id = c.campaign_id
JOIN ab_test_variants av ON marketing_events.variant_id = av.variant_id -- join on variant_id not campaign_id
WHERE c.campaign_type = 'ab_test' 
  AND marketing_events.variant_id IS NOT NULL  -- NEW: Only include events with variant assignment
GROUP BY
  window_start,
  window_end,
  c.campaign_id,
  c.campaign_name,
  av.variant_name,
  av.variant_type;
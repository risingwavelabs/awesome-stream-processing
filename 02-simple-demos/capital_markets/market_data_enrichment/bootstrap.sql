CREATE TABLE IF NOT EXISTS raw_market_data (
  asset_id   INT,
  timestamp  TIMESTAMPTZ,
  price      DOUBLE PRECISION,
  volume     INT,
  bid_price  DOUBLE PRECISION,
  ask_price  DOUBLE PRECISION,
  PRIMARY KEY (asset_id, timestamp)
) WITH (
  connector = 'kafka',
  topic     = 'raw_market_data',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode          = 'earliest-offset'
) FORMAT PLAIN ENCODE JSON; :contentReference[oaicite:0]{index=0}


CREATE TABLE IF NOT EXISTS enrichment_data (
  asset_id              INT,
  sector                VARCHAR,
  historical_volatility DOUBLE PRECISION,
  sector_performance    DOUBLE PRECISION,
  sentiment_score       DOUBLE PRECISION,
  timestamp             TIMESTAMPTZ,
  PRIMARY KEY (asset_id, timestamp)
) WITH (xs
  connector = 'kafka',
  topic     = 'enrichment_data',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode          = 'earliest-offset'
) FORMAT PLAIN ENCODE JSON; :contentReference[oaicite:1]{index=1}

CREATE MATERIALIZED VIEW IF NOT EXISTS avg_price_bid_ask_spread AS
  SELECT
    asset_id,
    ROUND(AVG(price)  OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE INTERVAL '5 MINUTES' PRECEDING
    ),2) AS average_price,
    ROUND(AVG(ask_price - bid_price) OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE INTERVAL '5 MINUTES' PRECEDING
    ),2) AS bid_ask_spread,
    timestamp
  FROM raw_market_data;

CREATE MATERIALIZED VIEW IF NOT EXISTS rolling_volatility AS
  SELECT
    asset_id,
    ROUND(stddev_samp(price) OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE INTERVAL '15 MINUTES' PRECEDING
    ),2) AS rolling_volatility,
    timestamp
  FROM raw_market_data;

CREATE MATERIALIZED VIEW IF NOT EXISTS enriched_market_data AS
  SELECT
    r.asset_id,
    ap.average_price,
    (r.price - ap.average_price) / ap.average_price * 100   AS price_change,
    ap.bid_ask_spread,
    rv.rolling_volatility,
    e.sector_performance,
    e.sentiment_score,
    r.timestamp
  FROM raw_market_data AS r
  JOIN avg_price_bid_ask_spread AS ap
    ON r.asset_id = ap.asset_id
   AND r.timestamp BETWEEN ap.timestamp - INTERVAL '10 seconds'
                       AND ap.timestamp + INTERVAL '10 seconds'
  JOIN rolling_volatility AS rv
    ON r.asset_id = rv.asset_id
   AND r.timestamp BETWEEN rv.timestamp - INTERVAL '10 seconds'
                       AND rv.timestamp + INTERVAL '10 seconds'
  JOIN enrichment_data AS e
    ON r.asset_id = e.asset_id
   AND r.timestamp BETWEEN e.timestamp - INTERVAL '10 seconds'
                       AND e.timestamp + INTERVAL '10 seconds';
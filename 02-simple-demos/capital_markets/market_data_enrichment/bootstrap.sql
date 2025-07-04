-- Base tables
CREATE TABLE IF NOT EXISTS raw_market_data (
  asset_id INT,
  timestamp TIMESTAMPTZ,
  price NUMERIC,
  volume INT,
  bid_price NUMERIC,
  ask_price NUMERIC
);

CREATE TABLE IF NOT EXISTS enrichment_data (
  asset_id INT,
  sector VARCHAR,
  historical_volatility NUMERIC,
  sector_performance NUMERIC,
  sentiment_score NUMERIC,
  timestamp TIMESTAMPTZ
);

-- Materialized Views (live entirely inside RisingWave)
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
    rmd.asset_id,
    ap.average_price,
    (rmd.price - ap.average_price) / ap.average_price * 100 AS price_change,
    ap.bid_ask_spread,
    rv.rolling_volatility,
    ed.sector_performance,
    ed.sentiment_score,
    rmd.timestamp
  FROM raw_market_data AS rmd
  JOIN avg_price_bid_ask_spread AS ap
    ON rmd.asset_id = ap.asset_id
    AND rmd.timestamp BETWEEN ap.timestamp - INTERVAL '2 seconds' AND ap.timestamp + INTERVAL '2 seconds'
  JOIN rolling_volatility AS rv
    ON rmd.asset_id = rv.asset_id
    AND rmd.timestamp BETWEEN rv.timestamp - INTERVAL '2 seconds' AND rv.timestamp + INTERVAL '2 seconds'
  JOIN enrichment_data AS ed
    ON rmd.asset_id = ed.asset_id
    AND rmd.timestamp BETWEEN ed.timestamp - INTERVAL '2 seconds' AND ed.timestamp + INTERVAL '2 seconds';

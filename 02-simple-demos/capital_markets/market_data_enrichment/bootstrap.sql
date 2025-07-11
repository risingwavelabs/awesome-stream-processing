CREATE SOURCE raw_market_data (
  asset_id     INT,
  timestamp    TIMESTAMPTZ,
  price        DOUBLE,
  volume       INT,
  bid_price    DOUBLE,
  ask_price    DOUBLE
) WITH (
  connector = 'kafka',
  topic = 'raw_market_data',
  "properties.bootstrap.server" = 'kafka:9092',
  "scan.startup.mode"           = 'earliest-offset'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE enrichment_data (
    asset_id INT,
    sector VARCHAR,
    historical_volatility DOUBLE,
    sector_performance DOUBLE,
    sentiment_score DOUBLE,
    timestamp TIMESTAMPTZ
) WITH (
    connector = 'kafka',
    topic = 'enrichment_data',
    "properties.bootstrap.server" = 'kafka:9092',
    "scan.startup.mode"           = 'earliest-offset'
) FORMAT PLAIN ENCODE JSON;

-- MVs entirely in RW
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
    AND rmd.timestamp BETWEEN ap.timestamp - INTERVAL '10 seconds' AND ap.timestamp + INTERVAL '10 seconds'
  JOIN rolling_volatility AS rv
    ON rmd.asset_id = rv.asset_id
    AND rmd.timestamp BETWEEN rv.timestamp - INTERVAL '10 seconds' AND rv.timestamp + INTERVAL '10 seconds'
  JOIN enrichment_data AS ed
    ON rmd.asset_id = ed.asset_id
    AND rmd.timestamp BETWEEN ed.timestamp - INTERVAL '10 seconds' AND ed.timestamp + INTERVAL '10 seconds';


CREATE TABLE IF NOT EXISTS enriched_market_data_table (
  asset_id            INT,
  average_price       NUMERIC,
  price_change        NUMERIC,
  bid_ask_spread      NUMERIC,
  rolling_volatility  NUMERIC,
  sector_performance  NUMERIC,
  sentiment_score     NUMERIC,
  timestamp           TIMESTAMPTZ,
  PRIMARY KEY (asset_id, timestamp)
);


CREATE SINK enriched_market_data_table
INTO enriched_market_data_table
FROM enriched_market_data;
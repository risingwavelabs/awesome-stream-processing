CREATE TABLE avg_price_sink (
  asset_id INT,
  average_price NUMERIC,
  bid_ask_spread NUMERIC,
  timestamp TIMESTAMPTZ
);

CREATE TABLE rolling_volatility_sink (
  asset_id INT,
  rolling_volatility NUMERIC,
  timestamp TIMESTAMPTZ
);

CREATE TABLE enriched_market_data_sink (
  asset_id INT,
  average_price NUMERIC,
  price_change NUMERIC,
  bid_ask_spread NUMERIC,
  rolling_volatility NUMERIC,
  sector_performance NUMERIC,
  sentiment_score NUMERIC,
  timestamp TIMESTAMPTZ
);

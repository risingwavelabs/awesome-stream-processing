-- Raw market data table
CREATE TABLE raw_market_data (
    asset_id INTEGER,
    timestamp TIMESTAMPTZ,
    price DECIMAL,
    volume INTEGER,
    bid_price DECIMAL,
    ask_price DECIMAL
);

-- Enrichment data table
CREATE TABLE enrichment_data (
    asset_id INTEGER,
    sector VARCHAR,
    historical_volatility DECIMAL,
    sector_performance DECIMAL,
    sentiment_score DECIMAL,
    timestamp TIMESTAMPTZ
);
CREATE TABLE trade_data (
    trade_id INT,
    asset_id INT,
    timestamp TIMESTAMPTZ,
    price NUMERIC,
    volume INT,
    buyer_id INT,
    seller_id INT
);

CREATE TABLE market_data (
    asset_id INT,
    timestamp TIMESTAMPTZ,
    bid_price NUMERIC,
    ask_price NUMERIC,
    price NUMERIC,
    rolling_volume INT
);

CREATE MATERIALIZED VIEW unusual_volume AS
SELECT
    trade_id,
    asset_id,
    volume,
    CASE WHEN volume > AVG(volume) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '10 MINUTES' PRECEDING) * 1.5
         THEN TRUE ELSE FALSE END AS unusual_volume,
    timestamp
FROM
    trade_data;


CREATE MATERIALIZED VIEW price_spike AS
SELECT
    asset_id,
    (MAX(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING) -
     MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING)) /
     MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING) AS percent_change,
    CASE 
        WHEN 
            (MAX(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING) -
             MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING)) /
             MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING) * 100 > 5 
        THEN TRUE 
        ELSE FALSE 
    END AS if_price_spike,
    timestamp
FROM
    market_data;

CREATE MATERIALIZED VIEW spoofing_detection AS
SELECT
    m.asset_id,
    m.timestamp,
    CASE WHEN ABS(m.bid_price - m.ask_price) < 0.2 AND rolling_volume < AVG(rolling_volume) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '10 MINUTES' PRECEDING) * 0.8
         THEN TRUE ELSE FALSE END AS potential_spoofing
FROM
    market_data AS m;
-- This view calculates:
-- 1. Average price: The mean price during the 3-second window
-- 2. Bid-ask spread: The average difference between ask and bid prices
--    A wider spread typically indicates lower liquidity and higher trading costs
CREATE MATERIALIZED VIEW avg_price_bid_ask_spread AS
SELECT
    asset_id,
    ROUND(AVG(price), 2) AS average_price,
    ROUND(AVG(ask_price - bid_price), 2) AS bid_ask_spread,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM
    TUMBLE(raw_market_data, timestamp, '3 seconds')
GROUP BY asset_id, window_end;

-- Calculates price volatility over a 3-second window using standard deviation
-- Higher volatility indicates larger price swings and potentially higher risk
-- Lower volatility suggests more stable price action
CREATE MATERIALIZED VIEW rolling_volatility AS
SELECT
    asset_id,
    ROUND(stddev_samp(price), 2) AS rolling_volatility,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM
    TUMBLE(raw_market_data, timestamp, '3 seconds')
    GROUP BY asset_id, window_end;

-- Volume Weighted Average Price (VWAP) is a trading benchmark
-- Calculates average price weighted by volume, giving more importance 
-- to prices at which more trading occurred
-- Often used to determine if current price is relatively high or low
CREATE MATERIALIZED VIEW vwap AS
SELECT
    asset_id,
    ROUND(SUM(price * volume) / SUM(volume), 2) AS vwap,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM
    TUMBLE(raw_market_data, timestamp, '3 seconds')
GROUP BY asset_id, window_end;

-- Measures the directional movement of price within each 3-second window
-- Calculated as percentage change between first and last price
-- Positive momentum indicates upward trend, negative indicates downward trend
-- Helps identify short-term price trends and potential trading opportunities
CREATE MATERIALIZED VIEW price_momentum AS
WITH window_prices AS (
    SELECT 
        asset_id,
        timestamp,
        price,
        window_end,
        FIRST_VALUE(price) OVER (PARTITION BY asset_id, window_end ORDER BY timestamp) AS start_price,
        LAST_VALUE(price) OVER (PARTITION BY asset_id, window_end ORDER BY timestamp RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS end_price
    FROM 
        TUMBLE(raw_market_data, timestamp, '3 seconds')
)
SELECT 
    asset_id,
    ROUND(
        ((end_price - start_price) / start_price) * 100,
        2
    ) AS price_momentum_pct,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM 
    window_prices
GROUP BY asset_id, window_end, start_price, end_price;

-- Provides a comprehensive view of trading activity including:
-- 1. Trade count: Number of trades executed
-- 2. Total volume: Sum of all traded quantities
-- 3. Price range: Difference between highest and lowest prices
-- Higher values generally indicate more active/liquid trading periods
CREATE MATERIALIZED VIEW trading_activity AS
SELECT
    asset_id,
    COUNT(*) AS trade_count,
    ROUND(SUM(volume), 2) AS total_volume,
    ROUND(MAX(price) - MIN(price), 2) AS price_range,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM
    TUMBLE(raw_market_data, timestamp, '3 seconds')
GROUP BY asset_id, window_end;

-- Sentiment-Adjusted Price Momentum
-- Combines price momentum with sentiment score to provide a more comprehensive
-- view of price direction. Higher sentiment scores amplify positive momentum
-- and dampen negative momentum, reflecting market psychology
CREATE MATERIALIZED VIEW sentiment_adjusted_momentum AS
WITH price_changes AS (
    SELECT 
        asset_id,
        timestamp,
        price,
        window_end,
        FIRST_VALUE(price) OVER (
            PARTITION BY asset_id, window_end 
            ORDER BY timestamp
        ) AS start_price,
        LAST_VALUE(price) OVER (
            PARTITION BY asset_id, window_end 
            ORDER BY timestamp 
            RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS end_price
    FROM 
        TUMBLE(raw_market_data, timestamp, '3 seconds')
)
SELECT 
    pc.asset_id,
    ROUND(
        ((pc.end_price - pc.start_price) / pc.start_price * 100) * 
        (1 + ed.sentiment_score), -- Adjust momentum by sentiment
        2
    ) AS adjusted_momentum,
    ed.sentiment_score,
    to_char(pc.window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM 
    price_changes pc
JOIN 
    enrichment_data ed ON pc.asset_id = ed.asset_id
GROUP BY 
    pc.asset_id, pc.window_end, pc.start_price, 
    pc.end_price, ed.sentiment_score;

-- Sector-Relative Performance
-- Compares an asset's price performance against its sector's performance
-- Positive values indicate outperformance, negative values indicate underperformance
-- Helps identify strong/weak assets within their sectors
CREATE MATERIALIZED VIEW sector_relative_performance AS
WITH asset_performance AS (
    SELECT 
        raw_market_data.asset_id,
        ed.sector,
        ROUND(
            ((MAX(raw_market_data.price) - MIN(raw_market_data.price)) / MIN(raw_market_data.price) * 100),
            2
        ) AS price_change_pct,
        ed.sector_performance,
        window_end
    FROM 
        TUMBLE(raw_market_data, timestamp, '3 seconds')
    JOIN 
        enrichment_data ed ON raw_market_data.asset_id = ed.asset_id
    GROUP BY 
        raw_market_data.asset_id, ed.sector, ed.sector_performance, window_end
)
SELECT 
    asset_id,
    sector,
    price_change_pct,
    sector_performance,
    ROUND(
        price_change_pct - sector_performance,
        2
    ) AS relative_performance,
    to_char(window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end
FROM 
    asset_performance;

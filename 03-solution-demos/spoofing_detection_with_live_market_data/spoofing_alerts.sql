-- Spoofing detection SQL
CREATE MATERIALIZED VIEW spoofing_alerts AS
WITH order_events AS (
    SELECT
        md.ts_event,
        md.symbol,
        md.exchange,
        md.side,
        md.price,
        md.size,
        md.event_type,
        bbo_mv.bid_px_00,
        bbo_mv.ask_px_00
    FROM market_data_new md
    LEFT JOIN bbo_mv
      ON CAST(md.symbol AS VARCHAR) = bbo_mv.symbol
     AND md.exchange = bbo_mv.exchange
     AND bbo_mv.ts_event >= md.ts_event - INTERVAL '1 second'
     AND bbo_mv.ts_event <= md.ts_event
    WHERE md.event_type IN ('add', 'cancel')
),
potential_spoofing AS (
    SELECT
        symbol,
        exchange,
        window_start,
        COUNT(*) AS num_cancellations
    FROM TUMBLE(order_events, ts_event, INTERVAL '5 seconds')
    WHERE
        event_type = 'cancel'
        AND size > 1000
        AND (
            (side = 'bid' AND ABS(price - bid_px_00) < 0.01 * bid_px_00) OR
            (side = 'ask' AND ABS(price - ask_px_00) < 0.01 * ask_px_00)
        )
    GROUP BY symbol, exchange, window_start
    HAVING COUNT(*) > 1
)
SELECT
    window_start,
    symbol,
    exchange,
    num_cancellations
FROM potential_spoofing;
SET TIME ZONE 'Asia/Shanghai';

DROP MATERIALIZED VIEW IF EXISTS block_stats;
DROP MATERIALIZED VIEW IF EXISTS tx_2min_stats;
DROP MATERIALIZED VIEW IF EXISTS tx_5s_count;

DROP INDEX IF EXISTS idx_tx_slot;
DROP INDEX IF EXISTS idx_tx_signature;

DROP MATERIALIZED VIEW tx;

DROP SOURCE IF EXISTS txs;

CREATE SOURCE txs
(
    transactions     JSONB
) WITH (
      connector = 'kafka',
      topic = 'tx',
      properties.bootstrap.server = 'localhost:9092',
      scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE MATERIALIZED VIEW tx AS
SELECT
    tx->>'slot'                         AS slot,
    (tx->>'blockTime')::TIMESTAMPTZ     AS blockTime,
    tx->>'tx_type'                      AS tx_type,
    tx->>'signature'                    AS signature,
    tx->>'sender'                       AS sender,
    tx->>'receiver'                     AS receiver,
    (tx->>'amount')::NUMERIC            AS amount,
    tx->>'fee'                          AS fee
FROM (
    SELECT jsonb_array_elements(transactions) AS tx
    FROM txs
    );

CREATE INDEX idx_tx_slot ON tx (slot);
CREATE INDEX idx_tx_signature ON tx (signature);

CREATE MATERIALIZED VIEW block_stats AS
SELECT slot,
       COUNT(CASE WHEN tx_type = 'SOL Transfer' THEN 1 END)                              AS sol_tx_count,
       COALESCE(SUM(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_total_amount,
       COALESCE(ROUND(AVG(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0))       AS sol_avg_amount,
       COALESCE(MAX(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_max_amount,
       COALESCE(MIN(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_min_amount,

       COUNT(CASE WHEN tx_type = 'SPL-Token Transfer' THEN 1 END)                        AS spl_tx_count,
       COALESCE(SUM(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_total_amount,
       COALESCE(ROUND(AVG(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)) AS spl_avg_amount,
       COALESCE(MAX(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_max_amount,
       COALESCE(MIN(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_min_amount
FROM tx
GROUP BY slot;

CREATE MATERIALIZED VIEW tx_2min_stats AS
SELECT window_start,
       window_end,

       COUNT(CASE WHEN tx_type = 'SOL Transfer' THEN 1 END)                              AS sol_tx_count,
       COALESCE(SUM(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_total_amount,
       COALESCE(ROUND(AVG(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0))       AS sol_avg_amount,
       COALESCE(MAX(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_max_amount,
       COALESCE(MIN(CASE WHEN tx_type = 'SOL Transfer' THEN amount END), 0)              AS sol_min_amount,

       COUNT(CASE WHEN tx_type = 'SPL-Token Transfer' THEN 1 END)                        AS spl_tx_count,
       COALESCE(SUM(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_total_amount,
       COALESCE(ROUND(AVG(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)) AS spl_avg_amount,
       COALESCE(MAX(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_max_amount,
       COALESCE(MIN(CASE WHEN tx_type = 'SPL-Token Transfer' THEN amount END), 0)        AS spl_min_amount
FROM HOP(tx, blockTime, INTERVAL '1 minute', INTERVAL '2 minutes')
GROUP BY window_start, window_end;

CREATE MATERIALIZED VIEW tx_5s_count AS
SELECT window_start,
       COUNT(*) AS tx_count
FROM TUMBLE(tx, blocktime, INTERVAL '5 seconds')
GROUP BY window_start;

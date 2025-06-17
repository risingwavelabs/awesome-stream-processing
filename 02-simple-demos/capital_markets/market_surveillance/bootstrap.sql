CREATE TABLE surveillance_input (
  asset_id INT,
  timestamp TIMESTAMPTZ,
  price NUMERIC,
  volume INT
);

CREATE MATERIALIZED VIEW suspicious_activity AS
SELECT
  asset_id,
  timestamp,
  volume,
  price,
  CASE
    WHEN volume > 100000 THEN 'high_volume'
    ELSE 'normal'
  END AS activity_flag
FROM surveillance_input;
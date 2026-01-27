DROP SINK IF EXISTS sink_network_anomalies;

DROP CONNECTION IF EXISTS iceberg_minio_conn;

DROP MATERIALIZED VIEW IF EXISTS network_anomalies;
DROP MATERIALIZED VIEW IF EXISTS device_metrics_10s;

DROP SOURCE IF EXISTS network_metrics_source;

CREATE SOURCE network_metrics_source (
    device_id VARCHAR,
    timestamp TIMESTAMP,
    src_ip VARCHAR,
    dst_ip VARCHAR,
    protocol VARCHAR,
    latency_ms FLOAT,
    packet_loss_rate FLOAT,
    bandwidth_usage_percent FLOAT,
    flow_bytes BIGINT
) WITH (
    connector = 'kafka',
    topic = 'network_metrics',
    properties.bootstrap.server = 'localhost:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

CREATE MATERIALIZED VIEW device_metrics_10s AS
SELECT
    device_id,
    window_start,
    window_end,
    AVG(latency_ms) AS avg_latency_ms,
    AVG(packet_loss_rate) AS avg_packet_loss_rate,
    AVG(bandwidth_usage_percent) AS avg_bandwidth_usage,
    SUM(flow_bytes) AS total_flow_bytes
FROM TUMBLE(network_metrics_source, timestamp, INTERVAL '10 seconds')
GROUP BY device_id, window_start, window_end;

CREATE MATERIALIZED VIEW network_anomalies AS
SELECT
    device_id,
    window_start,
    window_end,
    avg_latency_ms,
    avg_packet_loss_rate,
    avg_bandwidth_usage,
    avg_latency_ms > 100 AS is_high_latency,
    avg_packet_loss_rate > 5 AS is_high_packet_loss,
    avg_bandwidth_usage > 90 AS is_bandwidth_saturation
FROM device_metrics_10s
WHERE avg_latency_ms > 100 OR avg_packet_loss_rate > 5 OR avg_bandwidth_usage > 90;

CREATE CONNECTION iceberg_minio_conn WITH (
    type = 'iceberg',
    catalog.type = 'rest',
    catalog.uri = 'http://localhost:8181/catalog',
    warehouse.path = 'rw_iceberg',
    s3.endpoint = 'http://localhost:9000',
    s3.access.key = 'minioadmin',
    s3.secret.key = 'minioadmin',
    s3.region = 'us-east-1',
    s3.path.style.access = 'true'
);

CREATE SINK sink_network_anomalies
FROM network_anomalies
WITH (
    connector = 'iceberg',
    type = 'append-only',
    force_append_only = 'true',
    connection = public.iceberg_minio_conn,
    database.name = 'public',
    table.name = 'network_anomalies_history',
    create_table_if_not_exists = 'true'
);

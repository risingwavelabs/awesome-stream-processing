DROP MATERIALIZED VIEW IF EXISTS features_last_5min;
DROP MATERIALIZED VIEW IF EXISTS features;

DROP SOURCE IF EXISTS camera_stream;
DROP SOURCE IF EXISTS sensor_stream;

DROP MATERIALIZED VIEW IF EXISTS history_flow;
DROP TABLE IF EXISTS traffic_flow;

-- Camera stream
CREATE SOURCE camera_stream (
    timestamp TIMESTAMP,
    device_id VARCHAR,
    road_id VARCHAR,
    vehicle_type VARCHAR,
    license_plate VARCHAR,
    vehicle_speed_kph FLOAT,
) WITH (
    connector='kafka',
    topic='camera-data',
    properties.bootstrap.server='localhost:9092'
) FORMAT PLAIN ENCODE JSON;

--sensor stream
CREATE SOURCE sensor_stream (
    timestamp_entry TIMESTAMP,
    timestamp_exit TIMESTAMP,
    sensor_id VARCHAR,
    road_id VARCHAR,
    vehicle_speed_kph FLOAT,
) WITH (
    connector='kafka',
    topic='sensor-data',
    properties.bootstrap.server='localhost:9092'
) FORMAT PLAIN ENCODE JSON;

-- Set time zone
SET TIME ZONE 'Asia/Shanghai';

-- Calculate features
CREATE MATERIALIZED VIEW features AS
WITH ct AS (
    SELECT
        road_id,
        window_start,
        COUNT(*) AS vehicle_count
    FROM TUMBLE(sensor_stream,
                timestamp_entry,
                INTERVAL '1 minute'
         )
    GROUP BY road_id, window_start
)
SELECT ct.road_id AS road_id, ct.window_start AS window_start, ct.vehicle_count AS vehicle_count, spd.avg_speed_kph AS avg_speed_kph
FROM ct
    left join (
        SELECT
            road_id,
            window_start,
            AVG(vehicle_speed_kph) AS avg_speed_kph
        FROM TUMBLE(camera_stream,
                    timestamp,
                    INTERVAL '1 minute'
             )
        GROUP BY road_id, window_start
    ) spd
ON ct.road_id = spd.road_id and ct.window_start = spd.window_start;

CREATE MATERIALIZED VIEW features_last_5min AS
SELECT *
FROM features
WHERE window_start <= NOW() - INTERVAL '1 minute' AND window_start >= NOW() - INTERVAL '6 minutes';

CREATE TABLE traffic_flow (
    id BIGINT PRIMARY KEY,
    road_id VARCHAR,
    datetime TIMESTAMP,
    avg_speed_kph FLOAT,
    traffic_flow FLOAT,
    predicted_flow_next_minute FLOAT
) WITH (
    connector='kafka',
    topic='traffic-flow',
    properties.bootstrap.server='localhost:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE MATERIALIZED VIEW history_flow AS
SELECT road_id, datetime, avg_speed_kph, traffic_flow, predicted_flow_next_minute
FROM traffic_flow
WHERE datetime >= NOW() - INTERVAL '3 hours';

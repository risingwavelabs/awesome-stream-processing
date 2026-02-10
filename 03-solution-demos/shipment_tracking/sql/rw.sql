SET TIME ZONE 'Asia/Singapore';

DROP SCHEMA IF EXISTS eta CASCADE;
CREATE SCHEMA eta;


-- 1) GPS stream (JSON)
CREATE TABLE eta.gps_raw (
    event_ts TIMESTAMPTZ,
    vehicle_id VARCHAR,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    speed_kmh DOUBLE PRECISION
) WITH (
    connector = 'kafka',
    topic = 'gps_stream',
    properties.bootstrap.server = '127.0.0.1:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

-- 2) Traffic stream (JSON)
CREATE TABLE eta.traffic_raw (
    event_ts TIMESTAMPTZ,
    region_id VARCHAR,
    min_lat DOUBLE PRECISION,
    min_lon DOUBLE PRECISION,
    max_lat DOUBLE PRECISION,
    max_lon DOUBLE PRECISION,
    congestion DOUBLE PRECISION,
    traffic_speed_kmh DOUBLE PRECISION
) WITH (
    connector = 'kafka',
    topic = 'traffic_stream',
    properties.bootstrap.server = '127.0.0.1:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

-- 3) Order updates stream (JSON)
CREATE TABLE eta.order_updates_raw (
    order_id VARCHAR,
    vehicle_id VARCHAR,
    dest_lat DOUBLE PRECISION,
    dest_lon DOUBLE PRECISION,
    promised_ts TIMESTAMPTZ,
    status VARCHAR,
    updated_at TIMESTAMPTZ
) WITH (
    connector = 'kafka',
    topic = 'order_stream',
    properties.bootstrap.server = '127.0.0.1:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;


-- GPS events (typed)
CREATE MATERIALIZED VIEW eta.gps_events AS
SELECT
    event_ts,
    vehicle_id,
    lat,
    lon,
    speed_kmh,
    (
      CAST(FLOOR(lat / 0.002) AS BIGINT)::TEXT
      || '_' ||
      CAST(FLOOR(lon / 0.002) AS BIGINT)::TEXT
    ) AS grid_id
FROM eta.gps_raw;

-- Traffic events (typed)
CREATE MATERIALIZED VIEW eta.traffic_events AS
SELECT
    event_ts,
    region_id,
    min_lat,
    min_lon,
    max_lat,
    max_lon,
    congestion,
    traffic_speed_kmh,
    (
      CAST(FLOOR(((min_lat + max_lat) / 2) / 0.002) AS BIGINT)::TEXT
      || '_' ||
      CAST(FLOOR(((min_lon + max_lon) / 2) / 0.002) AS BIGINT)::TEXT
    ) AS grid_id
FROM eta.traffic_raw;

-- Order update events (typed)
CREATE MATERIALIZED VIEW eta.order_updates AS
SELECT
    order_id,
    vehicle_id,
    dest_lat,
    dest_lon,
    promised_ts,
    status,
    updated_at
FROM eta.order_updates_raw;

-- Latest order snapshot (one row per order_id)
CREATE MATERIALIZED VIEW eta.orders AS
SELECT
    order_id,
    vehicle_id,
    dest_lat,
    dest_lon,
    promised_ts,
    status,
    updated_at
FROM (
    SELECT *, row_number() OVER (PARTITION BY order_id ORDER BY updated_at DESC) AS rn
    FROM eta.order_updates
) t
WHERE rn = 1;

CREATE MATERIALIZED VIEW eta.vehicle_latest AS
SELECT
    vehicle_id,
    event_ts AS gps_ts,
    lat,
    lon,
    speed_kmh,
    grid_id
FROM (
    SELECT *, row_number() OVER (PARTITION BY vehicle_id ORDER BY event_ts DESC) AS rn
    FROM eta.gps_events
) t
WHERE rn = 1;

CREATE MATERIALIZED VIEW eta.traffic_latest AS
SELECT
    grid_id,
    region_id,
    event_ts AS traffic_ts,
    min_lat, min_lon, max_lat, max_lon,
    congestion,
    traffic_speed_kmh
FROM (
    SELECT *, row_number() OVER (PARTITION BY grid_id ORDER BY event_ts DESC) AS rn
    FROM eta.traffic_events
) t
WHERE rn = 1;



CREATE MATERIALIZED VIEW eta.order_eta_live AS
WITH joined AS (
    SELECT
        o.order_id,
        o.vehicle_id,
        o.status,
        o.dest_lat,
        o.dest_lon,
        o.promised_ts,
        o.updated_at,

        v.lat AS vehicle_lat,
        v.lon AS vehicle_lon,
        v.speed_kmh AS vehicle_speed_kmh,
        v.gps_ts,
        v.grid_id,

        t.region_id,
        coalesce(t.congestion, 0.0) AS congestion,
        coalesce(t.traffic_speed_kmh, v.speed_kmh) AS traffic_speed_kmh
    FROM eta.orders o
        JOIN eta.vehicle_latest v ON o.vehicle_id = v.vehicle_id
        LEFT JOIN eta.traffic_latest t ON v.grid_id = t.grid_id
),
calc_dist AS (
    SELECT
        *,
        -- Haversine distance (km)
        (2 * 6371 * asin(
          sqrt(
            power(sin(radians(dest_lat - vehicle_lat)/2), 2) +
            cos(radians(vehicle_lat)) * cos(radians(dest_lat)) *
            power(sin(radians(dest_lon - vehicle_lon)/2), 2)
          )
        )) AS distance_km
    FROM joined
),
calc_speed AS (
    SELECT
        *,
        -- Effective speed (km/h), floor at 5
        greatest(
          5.0,
          least(vehicle_speed_kmh, traffic_speed_kmh) * (1 - congestion * 0.6)
        ) AS effective_speed_kmh
    FROM calc_dist
),
calc_eta AS (
    SELECT
        *,
        -- Travel time (minutes)
        (distance_km / effective_speed_kmh * 60.0) AS eta_minutes
    FROM calc_speed
)
SELECT
    order_id,
    vehicle_id,
    status,
    dest_lat, dest_lon,
    promised_ts,
    updated_at,

    vehicle_lat, vehicle_lon,
    vehicle_speed_kmh,
    gps_ts,
    grid_id,

    region_id,
    congestion,
    traffic_speed_kmh,

    distance_km,
    effective_speed_kmh,
    eta_minutes,

    -- ETA timestamp based on event time
    (gps_ts + (eta_minutes * INTERVAL '1 minute')) AS eta_ts,

    -- Delay vs promised time (interval)
    ((gps_ts + (eta_minutes * INTERVAL '1 minute')) - promised_ts) AS delay_interval
FROM calc_eta;

-- Materialized view for machine metrics aggregation
CREATE MATERIALIZED VIEW monitoring_mv AS
SELECT
machine_id,
AVG(winding_temperature) AS avg_winding_temperature,
AVG(ambient_temperature) AS avg_ambient_temperature,
AVG(vibration_level) AS avg_vibration_level,
AVG(current_draw) AS avg_current_draw,
AVG(voltage_level) AS avg_voltage_level,
AVG(nominal_speed) AS avg_nominal_speed,
AVG(power_consumption) AS avg_power_consumption,
AVG(efficiency) AS avg_efficiency,
window_start,
window_end
FROM TUMBLE (shop_floor_machine_data,ts, INTERVAL '1 MINUTE')
GROUP BY machine_id, window_start,window_end;

-- Materialized view for maintenance alerts based on recent machine metrics
CREATE MATERIALIZED VIEW maintenance_mv AS 
WITH Historical_Averages AS (
    SELECT
        machine_id,
        AVG(winding_temperature) AS avg_winding_temp,
        AVG(vibration_level) AS avg_vibration,
        AVG(current_draw) AS avg_current_draw,
        AVG(power_consumption) AS avg_power_consumption,
        AVG(efficiency) AS avg_efficiency
    FROM shop_floor_machine_data
    WHERE ts < NOW() - INTERVAL '1' HOUR  -- Historical data for the last 1 hour 
    GROUP BY machine_id
),
Recent_Stats AS (
    SELECT
        machine_id,
        COUNT(*) AS event_count,
        window_start,
        window_end,
        AVG(winding_temperature) AS avg_winding_temp,
        AVG(vibration_level) AS avg_vibration,
        AVG(current_draw) AS avg_current_draw,
        AVG(power_consumption) AS avg_power_consumption,
        AVG(efficiency) AS avg_efficiency
    FROM TUMBLE (shop_floor_machine_data,ts, INTERVAL '1 MINUTES')
    GROUP BY machine_id, window_start,window_end
)
SELECT
    r.machine_id,
    r.window_start,
    r.window_end,
    r.avg_winding_temp,
    r.avg_vibration,
    r.avg_current_draw,
    r.avg_power_consumption,
    r.avg_efficiency,
    CASE
        WHEN r.avg_winding_temp > h.avg_winding_temp + 5 THEN 'Potential Overheating'
        WHEN r.avg_vibration > h.avg_vibration + 0.1 THEN 'Increased Vibration'
        WHEN r.avg_current_draw > h.avg_current_draw + 2 THEN 'Possible overcurrent condition'
        WHEN r.avg_efficiency < h.avg_efficiency - 5 THEN 'Efficiency Drop'
        ELSE 'Normal'
    END AS maintenance_alert
FROM
    Recent_Stats r
JOIN
    Historical_Averages h
ON
    r.machine_id = h.machine_id
WHERE
    r.avg_winding_temp > h.avg_winding_temp + 5 OR
    r.avg_vibration > h.avg_vibration + 0.1 OR
    r.avg_current_draw > h.avg_current_draw + 2 OR
    r.avg_efficiency < h.avg_efficiency - 5
ORDER BY
    r.window_end DESC;

-- Materialized view for anomaly detection in machine metrics
CREATE MATERIALIZED VIEW anomalies_mv AS
WITH Anomaly_Metrics AS (
    SELECT
        machine_id,
        window_start,
        window_end,
        AVG(winding_temperature) AS avg_winding_temp,
        AVG(vibration_level) AS avg_vibration,
        AVG(current_draw) AS avg_current_draw,
        AVG(voltage_level) AS avg_voltage_level,
        AVG(power_consumption) AS avg_power_consumption,
        STDDEV_POP(winding_temperature) AS stddev_winding_temp,
        STDDEV_POP(vibration_level) AS stddev_vibration,
        STDDEV_POP(current_draw) AS stddev_current_draw,
        STDDEV_POP(voltage_level) AS stddev_voltage_level,
        STDDEV_POP(power_consumption) AS stddev_power_consumption,
        MAX(winding_temperature) AS max_winding_temp,
        MAX(vibration_level) AS max_vibration,
        MAX(current_draw) AS max_current_draw,
        MAX(voltage_level) AS max_voltage_level,
        MAX(power_consumption) AS max_power_consumption
    FROM TUMBLE (shop_floor_machine_data,ts, INTERVAL '1 MINUTES')
    GROUP BY machine_id, window_start,window_end
),
Trend_Analysis AS (
    SELECT
        machine_id,
        window_start,
        window_end,
        avg_winding_temp,
        avg_vibration,
        avg_current_draw,
        avg_voltage_level,
        avg_power_consumption,
        stddev_winding_temp,
        stddev_vibration,
        stddev_current_draw,
        stddev_voltage_level,
        stddev_power_consumption,
        max_winding_temp,
        max_vibration,
        max_current_draw,
        max_voltage_level,
        max_power_consumption,
        LAG(avg_winding_temp, 1) OVER (PARTITION BY machine_id ORDER BY window_end) AS prev_avg_winding_temp,
        LAG(avg_vibration, 1) OVER (PARTITION BY machine_id ORDER BY window_end) AS prev_avg_vibration,
        LAG(avg_current_draw, 1) OVER (PARTITION BY machine_id ORDER BY window_end) AS prev_avg_current_draw,
        LAG(avg_voltage_level, 1) OVER (PARTITION BY machine_id ORDER BY window_end) AS prev_avg_voltage_level,
        LAG(avg_power_consumption, 1) OVER (PARTITION BY machine_id ORDER BY window_end) AS prev_avg_power_consumption
    FROM Anomaly_Metrics
)
SELECT
    machine_id,
    window_start,
    window_end,
    avg_winding_temp,
    avg_vibration,
    avg_current_draw,
    avg_voltage_level,
    avg_power_consumption,
    stddev_winding_temp,
    stddev_vibration,
    stddev_current_draw,
    stddev_voltage_level,
    stddev_power_consumption,
    max_winding_temp,
    max_vibration,
    max_current_draw,
    max_voltage_level,
    max_power_consumption,
    CASE
        WHEN max_winding_temp > avg_winding_temp + 3 * stddev_winding_temp THEN 'Anomalous Winding Temperature'
        WHEN max_vibration > avg_vibration + 3 * stddev_vibration THEN 'Anomalous Vibration Level'
        WHEN max_current_draw > avg_current_draw + 3 * stddev_current_draw THEN 'Anomalous Current Draw'
        WHEN max_voltage_level > avg_voltage_level + 3 * stddev_voltage_level THEN 'Anomalous Voltage Level'
        WHEN max_power_consumption > avg_power_consumption + 3 * stddev_power_consumption THEN 'Anomalous Power Consumption'
        WHEN (avg_winding_temp - prev_avg_winding_temp) > 2 * stddev_winding_temp THEN 'Rising Winding Temperature'
        WHEN (avg_vibration - prev_avg_vibration) > 2 * stddev_vibration THEN 'Increasing Vibration'
        WHEN (avg_current_draw - prev_avg_current_draw) > 2 * stddev_current_draw THEN 'Rising Current Draw'
        WHEN (avg_voltage_level - prev_avg_voltage_level) > 2 * stddev_voltage_level THEN 'Rising Voltage Level'
        WHEN (avg_power_consumption - prev_avg_power_consumption) > 2 * stddev_power_consumption THEN 'Rising Power Consumption'
        ELSE 'Normal'
    END AS anomaly_alert
FROM Trend_Analysis
WHERE
    max_winding_temp > avg_winding_temp + 3 * stddev_winding_temp OR
    max_vibration > avg_vibration + 3 * stddev_vibration OR
    max_current_draw > avg_current_draw + 3 * stddev_current_draw OR
    max_voltage_level > avg_voltage_level + 3 * stddev_voltage_level OR
    max_power_consumption > avg_power_consumption + 3 * stddev_power_consumption OR
    (avg_winding_temp - prev_avg_winding_temp) > 2 * stddev_winding_temp OR
    (avg_vibration - prev_avg_vibration) > 2 * stddev_vibration OR
    (avg_current_draw - prev_avg_current_draw) > 2 * stddev_current_draw OR
    (avg_voltage_level - prev_avg_voltage_level) > 2 * stddev_voltage_level OR
    (avg_power_consumption - prev_avg_power_consumption) > 2 * stddev_power_consumption
ORDER BY
    window_end DESC;

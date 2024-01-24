-- This creates a materialized view named "iot_mv" based on the "iot_source" to incrementally store all incoming data and to perform analysis.

CREATE MATERIALIZED VIEW iot_mv AS
SELECT 
    device_Id, 
    temperature,
    humidity,
    ts 
FROM iot_source;

-- 
CREATE MATERIALIZED VIEW avg_temperature_mv AS
SELECT deviceId, AVG(temperature) AS avg_temperature
window_start, window_end
FROM TUMBLE (iot_mv, ts, INTERVAL '1 MINUTES')
WHERE deviceId ='sensor1'
GROUP BY deviceId,window_start, window_end;

CREATE MATERIALIZED VIEW avg_humidity_mv AS
SELECT deviceId, AVG(humidity) AS avg_humidity
window_start, window_end
FROM TUMBLE (iot_mv, ts, INTERVAL '1 MINUTES')
WHERE deviceId ='sensor2'
GROUP BY deviceId,window_start, window_end;  

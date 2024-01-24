
SELECT 
    deviceId, 
    temperature,
    ts 
from iot_mv
WHERE deviceId ='sensor1'
limit 5;


SELECT 
    deviceId, 
    temperature,
    ts 
from iot_mv
WHERE deviceId ='sensor2'
limit 5;

SELECT * FROM avg_temperature_mv LIMIT 5;

SELECT * FROM avg_humidity_mv LIMIT 5;

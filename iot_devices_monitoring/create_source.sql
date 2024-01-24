-- This creates a source named "iot_source" to capture data from IoT devices.

CREATE SOURCE iot_source(
  deviceId VARCHAR,
  temperature INTEGER,
  humidity INTEGER,
  ts TIMESTAMPTZ
)
WITH (
  connector = 'kafka',
  topic = 'iot_devices', 
  properties.bootstrap.server = 'message_queue:29092',
  scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

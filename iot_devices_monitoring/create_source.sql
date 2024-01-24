
CREATE SOURCE iot_source(
  deviceId VARCHAR,
  temperature VARCHAR,
  humidity VARCHAR,
  ts TIMESTAMPTZ
)
WITH (
  connector = 'kafka',
  topic = 'iot_devices', 
  properties.bootstrap.server = 'message_queue:29092',
  can.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
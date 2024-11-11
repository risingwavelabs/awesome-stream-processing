CREATE TABLE shop_floor_machine_data (
machine_id VARCHAR,
winding_temperature INT,
ambient_temperature INT,
vibration_level FLOAT,
current_draw FLOAT,
voltage_level FLOAT,
nominal_speed FLOAT,
power_consumption FLOAT,
efficiency FLOAT,
ts TIMESTAMP
)
WITH (
connector='mqtt',
url='tcp://mqtt-server',
topic= 'factory/machine_data',
qos = 'at_least_once',
) FORMAT PLAIN ENCODE JSON;

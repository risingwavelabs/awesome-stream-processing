-- combined_passenger_flight_data: Streams full passenger flight details from a Solace topic in JSON format.
CREATE TABLE combined_passenger_flight_data (
    flight_id VARCHAR,
    flight_number VARCHAR,
    carrier_code VARCHAR,
    flight_date DATE,
    origin VARCHAR,
    passenger_ref_number VARCHAR,
    departure_time TIMESTAMPTZ,
    opted_in BOOLEAN,
    contact_info VARCHAR
)
WITH (
    connector = 'mqtt',
    topic = 'passenger_full_details',
    url = 'ssl://xxxxxxxxxx:8883',
    username='solace-cloud-client',
    password='xxxxxxxxxxxx', 
    qos = 'at_least_once'
) FORMAT PLAIN ENCODE JSON;

-- combined_passenger_flight_data: Streams full passenger flight details from a Solace topic in JSON format.
CREATE TABLE passenger_checkin_data (
    flight_id VARCHAR,
    flight_number VARCHAR,
    carrier_code VARCHAR,
    flight_date DATE,
    passenger_ref_number VARCHAR,
    checkin_time TIMESTAMPTZ,
    class VARCHAR
) WITH (
    connector = 'mqtt',
    topic = 'passenger_checkin',
    url = 'ssl://xxxxxxxxxx:8883',
    username='solace-cloud-client',
    password='xxxxxxxxxxxx', 
    qos = 'at_least_once'
) FORMAT PLAIN ENCODE JSON;

-- meal_availability: Streams meal availability updates from a Solace topic in JSON format.
CREATE TABLE meal_availability (
    flight_id VARCHAR,
    flight_number VARCHAR,
    carrier_code VARCHAR,
    flight_date TIMESTAMP,
    class VARCHAR,
    available_meals INT,
    update_time TIMESTAMP
)
WITH (
    connector = 'MQTT',
    topic = 'meal_availability',
    url = 'ssl://xxxxxxxxxx:8883'
    username='solace-cloud-client',
    password='xxxxxxxxxxxx', 
    qos = 'at_least_once'
) FORMAT PLAIN ENCODE JSON;


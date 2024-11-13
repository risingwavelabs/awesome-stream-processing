-- This creates a source named "aviation_source" with various columns to track flight information from the 'flights_tracking' topic encoded in JSON format. 

CREATE SOURCE aviation_source (
    flight_date VARCHAR,
    flight_status VARCHAR,
    
    departure_airport VARCHAR,
    departure_timezone VARCHAR,
    departure_iata VARCHAR,
    departure_icao VARCHAR,
    departure_terminal VARCHAR,
    departure_gate VARCHAR,
    departure_delay INTERVAL,
    departure_scheduled TIMESTAMP WITH TIME ZONE ,
    departure_estimated TIMESTAMP WITH TIME ZONE,
    departure_actual TIMESTAMP WITH TIME ZONE,
    departure_estimated_runway TIMESTAMP WITH TIME ZONE,
    departure_actual_runway TIMESTAMP WITH TIME ZONE,
    
    arrival_airport VARCHAR,
    arrival_timezone VARCHAR,
    arrival_iata VARCHAR,
    arrival_icao VARCHAR,
    arrival_terminal VARCHAR,
    arrival_gate VARCHAR,
    arrival_baggage VARCHAR,
    arrival_delay INTERVAL,
    arrival_scheduled TIMESTAMP WITH TIME ZONE,
    arrival_estimated TIMESTAMP WITH TIME ZONE,
    arrival_actual TIMESTAMP WITH TIME ZONE,
    arrival_estimated_runway TIMESTAMP WITH TIME ZONE,
    arrival_actual_runway TIMESTAMP WITH TIME ZONE,
    
    airline_name VARCHAR,
    airline_iata VARCHAR,
    airline_icao VARCHAR,
    
    flight_number VARCHAR,
    flight_iata VARCHAR,
    flight_icao VARCHAR,
    
    codeshared_airline_name VARCHAR,
    codeshared_airline_iata VARCHAR,
    codeshared_airline_icao VARCHAR,
    codeshared_flight_number VARCHAR,
    codeshared_flight_iata VARCHAR,
    flight_info VARCHAR
)
WITH(
  connector = 'kafka',
  topic = 'flights_tracking', 
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

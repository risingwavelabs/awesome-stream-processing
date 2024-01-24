-- This SQL code creates a materialized view named "aviation_mv" by selecting specific columns from the "aviation_source" source.

CREATE MATERIALIZED VIEW aviation_mv AS
    SELECT 
    flight_date,
    flight_status,
    
    departure_airport,
    departure_timezone,
    departure_iata,
    departure_icao,
    departure_scheduled,
    departure_estimated,
    
    arrival_airport,    
    arrival_timezone,
    arrival_iata,
    arrival_icao,
    arrival_scheduled,
    arrival_estimated,

    airline_name,
    airline_iata,
    airline_icao,
    
    flight_number,
    flight_iata,
    flight_icao,
    
    flight_info
    
FROM aviation_source;

-- This creates a materialized view named "airline_mv" by counting the total number of flights for each airline within 1-hour tumbling windows based on the scheduled arrival time.

CREATE MATERIALIZED VIEW airline_mv AS
SELECT airline_name,
COUNT(airline_name) AS total_flights,
window_start, window_end
FROM TUMBLE (aviation_mv, arrival_scheduled, INTERVAL '1 hour')
GROUP BY airline_name,window_start, window_end;

-- This creates a materialized view named "arrival_airport_mv" by counting the total number of flights arriving at each airport within 1-hour tumbling windows based on the scheduled arrival time.

CREATE MATERIALIZED VIEW arrival_airport_mv AS
SELECT arrival_airport, COUNT(arrival_airport) AS Total_Flights,
window_start, window_end
FROM TUMBLE (aviation_mv, arrival_scheduled, INTERVAL '1 hour')
GROUP BY arrival_airport,window_start, window_end
ORDER by Total_Flights DESC;

-- This creates a materialized view named "departure_airport_mv" by counting the total number of flights departing from each airport within 1-hour tumbling windows based on the scheduled departure time. 

CREATE MATERIALIZED VIEW departure_airport_mv AS
SELECT departure_airport, COUNT(departure_airport) AS Total_Flights,
window_start, window_end
FROM TUMBLE (aviation_mv, departure_scheduled, INTERVAL '1 hour')
GROUP BY departure_airport,window_start, window_end
ORDER by Total_Flights DESC;

-- Airline_Flight_Counts: Aggregates the total number of flights per airline in hourly intervals, ordered by the highest flight counts.
CREATE MATERIALIZED VIEW Airline_Flight_Counts
SELECT airline_name,
COUNT(airline_name) AS total_flights,
window_start, window_end
FROM TUMBLE (flight_tracking_source, arrival_scheduled, INTERVAL '1 hour')
GROUP BY airline_name,window_start, window_end
ORDER BY total_flights desc;


-- Airport_Summary: Provides hourly summaries of flight arrivals and departures at each airport, sorted by the highest counts of arriving and departing flights.
CREATE MATERIALIZED VIEW Airport_Summary
WITH ArrivalCounts AS (
    SELECT 
        arrival_airport, 
        COUNT(arrival_airport) AS total_flights_arrival,
        window_start, 
        window_end
    FROM 
        TUMBLE (flight_tracking_source, arrival_scheduled, INTERVAL '1 hour')
    GROUP BY 
        arrival_airport, 
        window_start, 
        window_end
),
DepartureCounts AS (
    SELECT 
        departure_airport, 
        COUNT(departure_airport) AS total_flights_departure,
        window_start, 
        window_end
    FROM 
        TUMBLE (flight_tracking_source, arrival_scheduled, INTERVAL '1 hour')
    GROUP BY 
        departure_airport, 
        window_start, 
        window_end
)
SELECT 
    ArrivalCounts.arrival_airport,
    ArrivalCounts.total_flights_arrival,
    DepartureCounts.departure_airport,
    DepartureCounts.total_flights_departure,
    ArrivalCounts.window_start,
    ArrivalCounts.window_end
FROM 
    ArrivalCounts
INNER JOIN 
    DepartureCounts ON ArrivalCounts.window_start = DepartureCounts.window_start 
    AND ArrivalCounts.window_end = DepartureCounts.window_end 
    AND ArrivalCounts.arrival_airport = DepartureCounts.departure_airport
ORDER BY 
    ArrivalCounts.total_flights_arrival DESC,
    DepartureCounts.total_flights_departure DESC;


-- Timezone_Summary: Displays hourly summaries of flight arrivals and departures by time zone, with results sorted by the highest counts in each time zone.
CREATE MATERIALIZED VIEW Timezone_Summary
WITH ArrivalCounts AS (
    SELECT 
        arrival_timezone, 
        COUNT(arrival_timezone) AS total_flights_arrival,
        window_start, 
        window_end
    FROM 
        TUMBLE (flight_tracking_source, arrival_scheduled, INTERVAL '1 hour')
    GROUP BY 
        arrival_timezone, 
        window_start, 
        window_end
),
DepartureCounts AS (
    SELECT 
        departure_timezone, 
        COUNT(departure_timezone) AS total_flights_departure,
        window_start, 
        window_end
    FROM 
        TUMBLE (flight_tracking_source, arrival_scheduled, INTERVAL '1 hour')
    GROUP BY 
        departure_timezone, 
        window_start, 
        window_end
)
SELECT 
    ArrivalCounts.arrival_timezone,
    ArrivalCounts.total_flights_arrival,
    DepartureCounts.departure_timezone,
    DepartureCounts.total_flights_departure,
    ArrivalCounts.window_start,
    ArrivalCounts.window_end
FROM 
    ArrivalCounts
INNER JOIN 
    DepartureCounts ON ArrivalCounts.window_start = DepartureCounts.window_start 
    AND ArrivalCounts.window_end = DepartureCounts.window_end 
    AND ArrivalCounts.arrival_timezone = DepartureCounts.departure_timezone
ORDER BY 
    ArrivalCounts.total_flights_arrival DESC,
    DepartureCounts.total_flights_departure DESC;

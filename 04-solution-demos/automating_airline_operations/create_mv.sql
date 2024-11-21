-- This MV dentifies passengers who opted in for notifications and have flights departing within 48 to 72 hours from the current time, providing details such as flight information and contact info.
CREATE MATERIALIZED VIEW checkin_open_notification AS
SELECT flight_id, passenger_ref_number, flight_number, carrier_code, departure_time, contact_info
FROM combined_passenger_flight_data
WHERE opted_in = TRUE
  AND departure_time <= NOW() - INTERVAL '48 hours'
  AND departure_time > NOW() - INTERVAL '72 hours';

-- This MV tracks the meal availability status for each flight and class by comparing the number of checked-in passengers to available meals, categorizing the result as either "Meal Shortage" or "Sufficient Meals."
CREATE MATERIALIZED VIEW flight_meal_status AS
SELECT
    p.flight_id,
    p.flight_number,
    p.class,
    COUNT(p.passenger_ref_number) AS checked_in_passengers,
    m.available_meals,
    CASE
        WHEN COUNT(p.passenger_ref_number) * 0.95 > m.available_meals THEN 'Meal Shortage'
        ELSE 'Sufficient Meals'
    END AS meal_status
FROM passenger_checkin AS p
LEFT JOIN meal_availability AS m
ON p.flight_id = m.flight_id AND p.class = m.class
GROUP BY p.flight_id, p.flight_number, p.class, m.available_meals;

-- This MV filters flights and classes from flight_meal_status with a "Meal Shortage" status, providing relevant details for notification or corrective action.
CREATE MATERIALIZED VIEW meal_shortage_notification AS
SELECT
    flight_id,
    flight_number,
    class,
    checked_in_passengers,
    available_meals,
    meal_status
FROM flight_meal_status
WHERE meal_status = 'Meal Shortage';  

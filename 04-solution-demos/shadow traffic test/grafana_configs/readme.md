# SQL queries

## Case 1

### Create source

Connect to data stream describing passenger and flight info.

```sql
CREATE SOURCE IF NOT EXISTS dcs_events (
	flight_number varchar,
	carrier_code varchar,
	departure_time timestamptz,
	origin varchar,
	destination varchar,
	passenger_ref_number varchar, 
	class varchar
)
WITH (
	connector='kafka',
	topic='dcs-events',
	properties.bootstrap.server='kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```
Connect to data stream containing additional passenger info.

```sql
CREATE SOURCE IF NOT EXISTS passenger_info (
	passenger_ref_number varchar, 
	opt_in varchar,
	contact_info varchar
) WITH (
	connector='kafka',
	topic='passenger-info',
	properties.bootstrap.server='kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```

### Create materialized view

Create a materialized view that joins the 2 data streams and filters for passengers who opted in for notifications and whose flights are D-48. The final materialized view contains the flight info for each passenger who opted in, as well as the passenger's email/contact info.

```sql
CREATE MATERIALIZED VIEW enriched_flight_passenger AS
SELECT
    d.flight_number,
    d.carrier_code,
    d.origin,
    d.passenger_ref_number,
    d.departure_time,
    p.contact_info,
    p.opt_in
FROM dcs_events AS d
LEFT JOIN passenger_info AS p
ON d.passenger_ref_number = p.passenger_ref_number
WHERE opt_in = 'TRUE'
	AND departure_time <= NOW() + INTERVAL '48 hours' 
	AND departure_time >= NOW();
```

## Case 2

### Create source

Connect to data stream describing passenger flight check-in status and flight info.

```sql
CREATE SOURCE IF NOT EXISTS dcs_events (
	flight_number varchar,
	carrier_code varchar,
	departure_time timestamptz,
	origin varchar,
	destination varchar,
	passenger_ref_number varchar, 
	class varchar,
	check_in timestamptz
)
WITH (
	connector='kafka',
	topic='dcs-events',
	properties.bootstrap.server='kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```
Connect to data stream describing meal availability for each class on each flight. 

```sql
CREATE SOURCE meal_availability (
	flight_number varchar,
	carrier_code varchar,
	departure_time timestamptz,
	origin varchar,
	destination varchar,
  class VARCHAR,
  available_meals INT
)
WITH (
    connector = 'kafka',
    topic = 'cms-events',
    properties.bootstrap.server = 'kafka:9092',
) FORMAT PLAIN ENCODE JSON;
```

### Create materialized views

Create a materialized view that counts how many passengers have checked in and if there's a meal shortage for each class on each flight. 

```sql
CREATE MATERIALIZED VIEW flight_meal_status AS
SELECT
    d.flight_number,
    d.carrier_code,
    d.departure_time,
    d.origin,
    d.destination,
    d.class,
    COUNT(d.check_in) AS checked_in_passengers,
    m.available_meals,
    CASE
        WHEN COUNT(d.check_in) * 0.95 > m.available_meals THEN 'Meal Shortage'
        ELSE 'Sufficient Meals'
    END AS meal_status
FROM dcs_events AS d
LEFT JOIN meal_availability AS m
ON d.flight_number = m.flight_number AND d.class = m.class 
	AND d.departure_time = m.departure_time AND d.origin = m.origin
	AND d.destination = m.destination AND d.carrier_code = m.carrier_code
GROUP BY d.carrier_code, d.flight_number, d.class, d.origin, 
	d.departure_time, d.destination, m.available_meals;
```
Create a materialized view that filters for instances where there is a meal shortage.

```sql
CREATE MATERIALIZED VIEW meal_shortage_notification AS
SELECT
    flight_number,
    carrier_code,
    origin,
    destination,
    class,
    checked_in_passengers,
    available_meals,
    meal_status
FROM flight_meal_status
WHERE meal_status = 'Meal Shortage';
```
```sql
create function count_days(a timestamptz)
returns numeric language sql as
$$SELECT EXTRACT(DAY FROM (DATE_TRUNC('month', a) + INTERVAL '1 month' - INTERVAL'1 day'))$$;
```

```sql
CREATE SOURCE energy_consume (
  consumption_time timestamptz, 
  meter_id integer, 
  energy_consumed double precision
  ) WITH (
    connector = 'kafka',
    topic = 'energy_consumed',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE energy_produce (
  production_time timestamptz, 
  meter_id integer, 
  energy_produced double precision
  ) WITH (
    connector = 'kafka',
    topic = 'energy_produced',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```

```sql
CREATE SOURCE pg_mydb WITH (
    connector = 'postgres-cdc',
    hostname = 'host.docker.internal',
    port = '5433',
    username = 'myuser',
    password = '123456',
    database.name = 'mydb'
);

CREATE TABLE customers (
  customer_id int,
  meter_id int,
  address varchar,
  price_plan varchar,
  PRIMARY KEY (customer_id)
) FROM pg_mydb TABLE 'public.customers';
```

```sql
CREATE MATERIALIZED VIEW energy_per_house AS
SELECT
	consumed.meter_id,
	energy_consumed,
	energy_produced,
	energy_consumed - energy_produced AS total_energy,
	consumed.window_end
FROM
    (
        SELECT
            meter_id,
            SUM(energy_consumed) AS energy_consumed,
            window_end
        FROM
            TUMBLE(
                energy_consume,
                consumption_time,
                INTERVAL '5' MINUTE)
        GROUP BY
            meter_id,
            window_end
    ) AS consumed
    JOIN (
        SELECT
            meter_id,
            SUM(energy_produced) AS energy_produced,
            window_end
        FROM
            TUMBLE(
	            energy_produce,
	            production_time,
	            INTERVAL '5' MINUTE) 
        GROUP BY
            meter_id,
            window_end
    ) AS produced ON consumed.meter_id = produced.meter_id
    AND consumed.window_end = produced.window_end;
```

```sql
CREATE MATERIALIZED VIEW energy_per_month AS
SELECT
	meter_id,
	SUM(total_energy) AS total_energy,
	date_trunc('month', window_end) AS month, 
	date_trunc('year', window_end) AS year
FROM energy_per_house
GROUP BY meter_id, date_trunc('month', window_end), date_trunc('year', window_end);
```

```sql
CREATE MATERIALIZED VIEW tiered_meters AS
SELECT
	customers.meter_id,
	total_energy,
	window_end
FROM energy_per_house 
LEFT JOIN customers ON energy_per_house.meter_id = customers.meter_id
WHERE customers.price_plan = 'tier';

CREATE MATERIALIZED VIEW tou_meters AS
SELECT
	customers.meter_id,
	total_energy,
	window_end
FROM energy_per_house 
LEFT JOIN customers ON energy_per_house.meter_id = customers.meter_id
WHERE customers.price_plan = 'time of use';
```

```sql
CREATE MATERIALIZED VIEW current_bill_tiered AS
WITH monthly_consumption AS (
    SELECT
        meter_id,
        date_trunc('month', window_end) AS month,
        date_trunc('year', window_end) AS year,
        SUM(total_energy) AS total_monthly_energy
    FROM
        tiered_meters
    GROUP BY
        meter_id,
        date_trunc('month', window_end),
        date_trunc('year', window_end)
),
estimated_bills AS (
    SELECT
        meter_id,
        total_monthly_energy,
        month,
        year,
        CASE
            WHEN total_monthly_energy <= 200 THEN total_monthly_energy * 0.2
            ELSE (200 * 0.20) + ((total_monthly_energy - 200) * 0.4)
        END AS estimated_bill_amount
    FROM
        monthly_consumption
)
SELECT
    meter_id,
    SUM(estimated_bill_amount) AS current_bill,
    month,
    year
FROM
    estimated_bills
GROUP BY
    meter_id,
    month, year;
```

```sql
CREATE MATERIALIZED VIEW estimated_tier_cost AS
WITH truncated_month AS (
    SELECT * FROM tiered_meters
    WHERE DATE_TRUNC('day', window_end) < (select max(date_trunc('day', window_end)) from energy_per_house)
),
daily_consumption AS (
    SELECT
        meter_id,
        DATE_TRUNC('day', window_end) AS days,
        SUM(total_energy) AS daily_energy
    FROM
        truncated_month
    GROUP BY
        meter_id,
        DATE_TRUNC('day', window_end)
),
projected_monthly_consumption AS (
    SELECT
        meter_id,
        SUM(daily_energy) AS total_energy_so_far ,
        (SUM(daily_energy) / date_part('day', max(days)))*count_days(DATE_TRUNC('month', days)) AS estimated_monthly_energy,
        DATE_TRUNC('month', days) AS month,
        DATE_TRUNC('year', days) AS year
    FROM
        daily_consumption
    GROUP BY
        meter_id, DATE_TRUNC('month', days), DATE_TRUNC('year', days)
),
estimated_bills AS (
    SELECT
        meter_id,
        estimated_monthly_energy,
        CASE
            WHEN estimated_monthly_energy <= 200 THEN estimated_monthly_energy * 0.2
            ELSE (200 * 0.20) + ((estimated_monthly_energy - 200) * 0.4)
        END AS estimated_bill_amount,
        month,
        year
    FROM
        projected_monthly_consumption
)
SELECT
    meter_id,
    SUM(estimated_bill_amount) AS estimated_total_bill,
    sum(estimated_monthly_energy) as estimated_total_energy,
    month
FROM
    estimated_bills
GROUP BY
    meter_id, month;
```

```sql
CREATE MATERIALIZED VIEW current_bill_tou AS
WITH hourly_cost AS (
    SELECT
        meter_id,
        date_trunc('month', window_end) AS month,
        date_trunc('year', window_end) AS year,
        CASE
            WHEN date_part('hour', window_end) BETWEEN 16 AND 20 THEN total_energy * 0.4
            ELSE total_energy * 0.2
        END AS cost
    FROM
        tou_meters
),
month_cost AS (
    SELECT
        meter_id,
        month,
        year,
        SUM(cost) AS monthly_cost
    FROM
        hourly_cost
    GROUP BY
        meter_id, month, year
)
SELECT
    month_cost.meter_id,
    monthly_cost,
    month_cost.month,
    month_cost.year
FROM
    month_cost
LEFT JOIN energy_per_month
ON month_cost.meter_id = energy_per_month.meter_id
	AND month_cost.month = energy_per_month.month
	AND month_cost.year = energy_per_month.year;
```

```sql
CREATE MATERIALIZED VIEW estimated_tou_cost AS
WITH truncated_month AS (
    SELECT * FROM tou_meters
    WHERE DATE_TRUNC('day', window_end) < (select max(date_trunc('day', window_end)) from energy_per_house)
),
daily_energy_consumption_hourly AS (
    SELECT
        meter_id,
        SUM(total_energy) AS daily_energy,
        date_part('hour', window_end) AS hour,
        DATE_part('day', window_end) AS day,
        DATE_TRUNC('month', window_end) AS month,
        DATE_TRUNC('year', window_end) AS year
    FROM
        truncated_month
    GROUP BY
        meter_id,
        date_part('hour', window_end),
        DATE_part('day', window_end),
        date_trunc('month', window_end),
        date_trunc('year', window_end)
)
SELECT
        meter_id,
        (SUM(
            CASE
                WHEN hour BETWEEN 16 AND 20 THEN daily_energy * 0.4
                ELSE daily_energy * 0.2
            END
        ) / max(day)) * count_days(month) AS estimated_monthly_bill,
        (sum(daily_energy)/max(day))*count_days(month) as estimated_total_energy,
        month
    FROM
        daily_energy_consumption_hourly
    GROUP BY
        meter_id,
        month;
```

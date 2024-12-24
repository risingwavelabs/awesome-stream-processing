### Create sources for the following 7 topics

trucks, drivers, shipments, warehouses, route, fuel, maint

```sql
CREATE SOURCE trucks (
  truck_id integer,
  truck_model varchar,
  capacity_tons integer,
  manufacture_year integer,
  current_location varchar
  ) WITH (
    connector = 'kafka',
    topic = 'trucks',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE driver (
  driver_id integer,
  driver_name varchar,
  license_number varchar,
  assigned_truck_id integer
  ) WITH (
    connector = 'kafka',
    topic = 'drivers',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE shipments (
  shipment_id varchar,
  origin varchar,
  destination varchar,
  shipment_weight integer,
  truck_id integer
  ) WITH (
    connector = 'kafka',
    topic = 'shipments',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE warehouses (
  warehouse_id varchar,
  location varchar,
  capacity_tons integer
  ) WITH (
    connector = 'kafka',
    topic = 'warehouses',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE route (
  route_id varchar,
  truck_id integer,
  driver_id integer,
  estimated_departure_time timestamptz,
  estimated_arrival_time timestamptz,
  distance_km integer
  ) WITH (
    connector = 'kafka',
    topic = 'route',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE fuel (
  fuel_log_id varchar,
  truck_id integer,
  fuel_date timestamptz,
  liters_filled integer,
  fuel_station varchar
  ) WITH (
    connector = 'kafka',
    topic = 'fuel',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE maint (
  maintenance_id varchar,
  truck_id integer,
  maintenance_date timestamptz,
  cost_usd integer
  ) WITH (
    connector = 'kafka',
    topic = 'maint',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```

### Straightforward 7-way join

```sql
create materialized view joined as
select
    t.truck_id,
    d.driver_id,
    d.driver_name,
    d.license_number,
    t.truck_model,
    t.capacity_tons, 
    t.current_location,
    s.shipment_id,
    s.origin,
    w.location as warehouse_location,
    w.capacity_tons as warehouse_capacity_tons,
    r.route_id,
    r.estimated_departure_time,
    r.distance_km,
    f.fuel_log_id,
    f.fuel_date,
    f.liters_filled,
    m.maintenance_id,
    m.maintenance_date,
    m.cost_usd
from driver d
left join
    trucks t on d.assigned_truck_id = t.truck_id
join 
    shipments s on t.truck_id = s.truck_id
join 
    route r on r.truck_id = t.truck_id
join
    warehouses w on s.destination = w.location
join 
    fuel f on f.truck_id = t.truck_id
join
    maint m on m.truck_id = t.truck_id
```

### Simple analysis, 6-way join

Find truck performance, cost analysis, and driver information

```sql
WITH TruckPerformance AS (
    SELECT
        t.truck_id,
        SUM(s.shipment_weight) AS total_shipment_weight,
        t.capacity_tons * 1000 AS max_capacity_weight 
    FROM
        trucks t
    LEFT JOIN
        shipments s ON t.truck_id = s.truck_id
    GROUP BY
        t.truck_id, t.capacity_tons
),
TruckCosts AS (
    SELECT
        t.truck_id,
        SUM(f.liters_filled * 1.2) AS total_fuel_cost,
        SUM(m.cost_usd) AS total_maintenance_cost
    FROM
        trucks t
    LEFT JOIN
        fuel f ON t.truck_id = f.truck_id
    LEFT JOIN
        maint m ON t.truck_id = m.truck_id
    GROUP BY
        t.truck_id
),
RouteDetails AS (
    SELECT
        r.truck_id,
        r.route_id,
        r.driver_id,
        r.estimated_departure_time,
        r.estimated_arrival_time,
        r.distance_km
    FROM
        route r
),
DriverDetails AS (
    SELECT
        d.driver_id,
        d.driver_name,
        d.license_number
    FROM
        driver d
)
SELECT
    t.truck_id,
    t.truck_model,
    tp.total_shipment_weight,
    tp.max_capacity_weight,
    ROUND((tp.total_shipment_weight * 100.0 / tp.max_capacity_weight), 2) AS capacity_utilization_percentage,
    tc.total_fuel_cost,
    tc.total_maintenance_cost,
    (tc.total_fuel_cost + tc.total_maintenance_cost) AS total_operational_cost,
    rd.route_id,
    rd.estimated_departure_time,
    rd.estimated_arrival_time,
    rd.distance_km,
    dd.driver_name,
    dd.license_number
FROM
    TruckPerformance tp
JOIN
    TruckCosts tc ON tp.truck_id = tc.truck_id
JOIN
    RouteDetails rd ON tp.truck_id = rd.truck_id
JOIN
    DriverDetails dd ON rd.driver_id = dd.driver_id
JOIN
    trucks t ON tp.truck_id = t.truck_id;
```

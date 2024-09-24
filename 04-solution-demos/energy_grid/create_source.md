## Connect to sources

Run each of the following queries to connect to the Kafka topics and PostgreSQL table. 

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


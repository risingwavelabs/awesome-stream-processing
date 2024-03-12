## Run Flink

Within this `flink` directory, run `docker compose up -d` to start the project.

Run `docker compose run sql-client` to start up the SQL client. Run the SQL queries included below line by line. 

```sql
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.interval' = '1min';

CREATE TABLE constant (
  order_id varchar,
  customer_id varchar,
  prod varchar,
  quant_in integer,
  tot_amnt_in double precision,
  ts varchar,
  order_time as to_timestamp(ts, 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
  ) WITH (
    'connector' = 'kafka',
    'topic' = 'purchase_constant',
    'properties.bootstrap.servers' = 'kafka:29093',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

CREATE TABLE varies (
  order_id varchar,
  customer_id varchar,
  prod varchar,
  quant_out integer,
  tot_amnt_out double precision,
  ts varchar, 
  sell_time as to_timestamp(ts, 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
) WITH (
    'connector' = 'kafka',
    'topic' = 'purchase_varying',
    'properties.bootstrap.servers' = 'kafka:29093',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

CREATE VIEW j3 AS
SELECT 
    c.customer_id,
    SUM(c.quant_in) - SUM(v.quant_out) AS quant_tot,
    SUM(c.tot_amnt_in) - SUM(v.tot_amnt_out) AS amnt_tot
FROM 
    constant AS c
JOIN 
    varies AS v ON c.customer_id = v.customer_id
GROUP BY 
    c.customer_id;

SELECT * FROM j3 LIMIT 30;
```


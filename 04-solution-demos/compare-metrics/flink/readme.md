CREATE TABLE constant (
  order_id varchar,
  customer_id varchar,
  prod varchar,
  quant_in integer,
  tot_amnt_in double precision
) WITH (
    'connector' = 'kafka',
    'topic' = 'purchase_constant',
    'properties.bootstrap.servers' = 'kafka:29092',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

CREATE TABLE varies (
  order_id varchar,
  customer_id varchar,
  prod varchar,
  quant_out integer,
  tot_amnt_out double precision
) WITH (
    'connector' = 'kafka',
    'topic' = 'purchase_varying',
    'properties.bootstrap.servers' = 'kafka:29092',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

create view v1 as
select order_id, customer_id, product, quantity
from constant
where total_amount > 30;

create view v2 as
select order_id, customer_id, product, quantity
from varies
where total_amount > 30;
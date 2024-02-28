# Use the following queries to create sources and materialized views

## Create sources that connects to the message producers

```sql
create source constant (
  order_id varchar,
  customer_id varchar,
  products STRUCT <product_id VARCHAR, quantity integer>,
  total_amount double precision,
  timestamp varchar
) with (
  connector = 'kafka',
  topic = 'purchase_constant',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;
```

```sql
create source varying (
  order_id varchar,
  customer_id varchar,
  products STRUCT <product_id VARCHAR, quantity integer>,
  total_amount double precision,
  timestamp varchar
) with (
  connector = 'kafka',
  topic = 'purchase_varying',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;
```

## Create materialized views

create materialized view joined_sources as
  select *
  from constant
  inner join varying on customer_id;
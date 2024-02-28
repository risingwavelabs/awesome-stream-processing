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

create materialized view c_mv as select * from constant;

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

create materialized view v_mv as select * from varying;
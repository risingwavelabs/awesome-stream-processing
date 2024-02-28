

CREATE SOURCE prometheus (
    labels STRUCT < __name__ VARCHAR,
    instance VARCHAR,
    job VARCHAR >,
    name VARCHAR,
    timestamp TIMESTAMPTZ,
    value VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'prometheus',
    properties.bootstrap.server = 'kafka:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

create source t (
  order_id varchar,
  customer_id varchar,
  products STRUCT <product_id VARCHAR, quantity integer>,
  total_amount double precision,
  timestamp varchar
) with (
  connector = 'kafka',
  topic = 'purchase',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;

create materialized view mv as select * from t;
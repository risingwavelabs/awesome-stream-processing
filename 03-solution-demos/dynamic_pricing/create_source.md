## Connect to sources

Run each of the following queries to connect to the Kafka topics and PostgreSQL table. 

```sql
CREATE SOURCE purchases (
  purchase_time timestamptz, 
  product_id integer,
  quantity_purchased integer,
  customer_id varchar
  ) WITH (
    connector = 'kafka',
    topic = 'purchases',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;

CREATE SOURCE restocks (
  restock_time timestamptz, 
  product_id integer, 
  quantity_restocked integer
  ) WITH (
    connector = 'kafka',
    topic = 'restocks',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```

```sql
CREATE TABLE product_inventory AS
SELECT * FROM
postgres_query(
  'host.docker.internal',
  '5433',
  'myuser',
  '123456',
  'mydb',
  'select * from product_inventory;'
);
```


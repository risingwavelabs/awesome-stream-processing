# Run RisingWave

Install the Confluent library for Python if it's not already installed on your device. 

```terminal
pip install confluent_kafka
```

The message producers also use the Python libraries random, json, datetime, time, and string, which are likely already downloaded. 

Run the `run_producers.py` python file to start producing messages.

Start [RisingWave via docker-compose](https://docs.risingwave.com/docs/dev/risingwave-docker-compose/). 

Run the queries below to start consuming messages from the message queue. 

Open [Grafana](http://localhost:3001) and open the pre-build RisingWave dashboard. The main performance metrics are tracked. Change the timeframe to 5 minutes to get a better view of how the metrics change over time. 

The varying data source starts and stops every 15 seconds. Both message producers approximately produce messages at a rate of 5 messages/second.

# Use the following queries to create sources and materialized views

## Create sources that connect to the message producers

```sql
create source constant (
  order_id varchar,
  customer_id varchar,
  prod_in varchar,
  quant_in integer,
  tot_amnt_in double precision,
  ts varchar
) with (
  connector = 'kafka',
  topic = 'purchase_constant',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;

create source varying (
  order_id varchar,
  customer_id varchar,
  prod_out varchar,
  quant_out integer,
  tot_amnt_out double precision,
  ts varchar
) with (
  connector = 'kafka',
  topic = 'purchase_varying',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;

create materialized view j3 as
SELECT  c.customer_id,
        sum(c.quant_in) - sum(v.quant_out) as quant_tot,
        sum(c.tot_amnt_in) - sum(v.tot_amnt_out) as amnt_tot
FROM constant as c
JOIN varying as v on c.customer_id = v.customer_id
group by c.customer_id;

select * from j3 limit 30;
```

A tumble function view (not included in flink)

```sql
create materialized view v2 as select
  order_id, customer_id, prod_out, quant_out, tot_amnt_out, ts::timestamptz
from varying;

create materialized view out_1min as 
select window_end, sum(quant_out) as quant_out, sum(tot_amnt_out) as tot_amnt_out
from tumble(v2, ts, interval '1' minute)
group by window_end;
```


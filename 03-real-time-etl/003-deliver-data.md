# Deliver and visualize your data

Finally, we can deliver the analysis results from the materialized view into downstream systems for storage, further processing, and visualization. RisingWave offers vast options for integrating with downstream systems to make it easy to include RisingWave into your technical stack no matter what platforms you currently use. 

In this demo, we will go over how to sink data to PostgreSQL for storage and additional processing.

## Sink to PostgreSQL

We can sink any data we want from RisingWave into PostgreSQL. Let us sink the data from the materialized view into a table in PostgreSQL. 

### Set up target table in PostgreSQL

Before creating a sink in RisingWave, a table in PostgreSQL must be created first. Then the data from RisingWave can be delivered to this table. The following query will create the table in PostgreSQL. 

```sql
CREATE TABLE website_vists (
    user_id INTEGER, 
    first_name VARCHAR, 
    last_name VARCHAR, 
    age INTEGER, 
    page_id VARCHAR, 
    num_actions INTEGER, 
    window_end TIMESTAMPTZ
);
```

### Create sink in RisingWave

Now we can use the `CREATE SINK` command in RisingWave to sink data from the materialized view to PostgreSQL. Here we create an `append-only` sink, meaning that only INSERT operations will be downstreamed. If we want to sink both UPDATE and INSERT operations, we can create an `upsert` sink. `upsert` sinks require a primary key to be defined while `append-only` sinks do not. 

Be sure to edit the `jdbc.url` accordingly with the username and password.

To learn more about how to sink data to PostgreSQL, see [Sink data from RisingWave to PostgreSQL](https://docs.risingwave.com/docs/current/sink-to-postgres/) from the official documentation.

```sql
CREATE SINK website_visits_pg_sink FROM website_visits_1min WITH (
    connector = 'jdbc',
    jdbc.url = 'jdbc:postgresql://postgres:5432/postgres?user=USERNAME&password=PASSWORD',
    table.name = 'website_vists',
    type = 'append_only'
);
```

## Connect to additional downstream systems

RisingWave offers built-in connectors to various downstream platforms. For instance, we can also sink the same `website_visits_1min` materialized view to ClickHouse for additional ad-hoc analysis by using a `CREATE SINK` command and making the appropriate configurations when setting up ClickHouse. Additionally, we can also connect to Grafana to create live dashboards. 

For a full list of supported integrations, see [Integrations](https://docs.risingwave.com/docs/dev/rw-integration-summary/).

For more details on how to sink to ClickHouse, see [Sink data from RisingWave to ClickHouse](https://docs.risingwave.com/docs/dev/sink-to-clickhouse/).

For more details on how to connect to Grafana, see [Configure Grafana to read data from RisingWave](https://docs.risingwave.com/docs/dev/grafana-integration/).

# Query the results from the original database

Alternatively, a foreign data wrapper (FDW) can be used in PostgreSQL to directly retrieve the analysis results from RisingWave. 

## Query results using a FDW 

We will continue to use the materialized view created in [Create and update a materialized view](/02-bring-analytics-closer-to-odb/001-create-mv-offload-analytics.md#create-and-update-a-materialized-view). 

Ensure that the PostgreSQL service supports the `postgres_fdw` extension. See [PostgreSQL's documentation](https://www.postgresql.org/docs/current/postgres-fdw.html) for more information. 

Start by running the following commands in the PostgreSQL database to prepare remote access. 

```sql
---Enable the postgres_fdw extension
CREATE EXTENSION postgres_fdw;

---Create a foreign table to connect to RisingWave
CREATE SERVER risingwave
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (host 'localhost', port '4566', dbname 'dev');

---Create a user mapping for the foreign server, mapping the RisingWave's user `root` to the PostgreSQL's user `postgres`
CREATE USER MAPPING FOR postgres
        SERVER risingwave
        OPTIONS (user 'root', password '');

---Import the definition of table and materialized view from RisingWave.
IMPORT FOREIGN SCHEMA public
    FROM SERVER risingwave INTO public;
```

You can check the list of foreign tables and materialized views.

```sql
SELECT * FROM pg_foreign_table;

 ftrelid | ftserver |                    ftoptions
---------+----------+-------------------------------------------------
   16413 |    16411 | {schema_name=public,table_name=atleast21}
   16416 |    16411 | {schema_name=public,table_name=pg_users}
```

Then, you can query directly from the materialized view in PostgreSQL. These results are the same as the results served in RisingWave.

```sql
SELECT * FROM atleast21;

     city      | avg_age 
---------------+---------
 Beijing       |   21.50
 San Francisco |   21.50
 New York      |   32.50
```

## Sink results back to PostgreSQL

If the performance of the foreign data wrapper does not meet your requirements, you can sink the results from RisingWave back to the PostgreSQL database. Although this method incurs additional overhead compared to querying RisingWave directly, there are a few benefits.

Storing the materialized view results as a table in PostgreSQL means the querying performance is more predictable. With PostgreSQL's ecosystem, you have access to some functionalities that RisingWave does not support, such as compatibility with Hasura and special indexes supported through PostgreSQL plugins.

When sinking data to PostgreSQL, you must have a destination table to sink data into. Ensure the schema of your destination table and materialized view match. The following SQL query creates a table in PostgreSQL that has the same data schema as the `atleast21` materialized view in RisingWave.

```sql
CREATE TABLE pg_atleast21 (
  city VARCHAR PRIMARY KEY,
  avg_age INT,
);
```

In RisingWave, use the `CREATE SINK` command to sink the results of the materialized view to the PostgreSQL table. The following JDBC URL is specified for the [newly created user](00-install-kafka-pg-rw.md#optional-create-a-database-user) `rw` with the password `abc123`.

```sql
CREATE SINK target_count_postgres_sink FROM atleast21 WITH (
    connector = 'jdbc',
    jdbc.url = 'jdbc:postgresql://postgres:5432/mydb?user=rw&password=abc123',
    table.name = 'pg_atleast21',
    type = 'upsert',
    primary_key = 'city'
);
```

For more information on how to sink data to PostgreSQL, see the [official documentation](https://docs.risingwave.com/docs/current/sink-to-postgres/).


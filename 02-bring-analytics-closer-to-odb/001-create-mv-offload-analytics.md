# Create materialized views to offload predefined analytics

## Prerequisites

To execute this demo, the following systems must be installed:
 - A RisingWave instance 
 - A PostgreSQL database

To learn how to install the listed requirements, see the related sections under [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md).

Additionally, RisingWave must be configured to read data from a PostgreSQL table. To set up the PostgreSQL table and RisingWave table, follow the instructions outlined in [Ingest data from PostgreSQL CDC into RisingWave](/00-get-started/02-ingest-pg-cdc.md).

## Create and update a materialized view

Next, we will create a materialized view based on the CDC table, `pg_users`, created in Ingest data from PostgreSQL CDC into RisingWave. The materialized view `over21` will filter for all users who are at least 21 years old.

```sql
CREATE MATERIALIZED VIEW atleast21 AS
SELECT * FROM pg_users
WHERE age >= 21;
```

If we query from this table, it should return all three users.

```sql
SELECT * FROM atleast21;

 id | age |    name
----+-----+-------------
  1 |  25 | John Doe
  2 |  30 | Jane Smith
  3 |  22 | Bob Johnson
```

Next, we will update the `pg_users` table in PostgreSQL by inserting a few new users. In the terminal window running PostgreSQL, run the following query to add new users to the table.

```sql
INSERT INTO users (name, age) VALUES
    ('Aaron Reed', 18),
    ('Denice Tucker', 21),
    ('Paul Lewis', 35);
```

These new changes will be reflected in the `atleast21` materialized view in RisingWave. We can check by querying from `atleast21` again. All users over the age of 21 should be listed.

```sql
 id | age |    name
----+-----+-------------
  1 |  25 | John Doe
  2 |  30 | Jane Smith
  3 |  22 | Bob Johnson
  5 |  21 | Denice Tucker
  6 |  35 | Paul Lewis
```

Describe:
- the advantage of the materialized view
    - Saves valuable OLTP system resources
    - Cost does not increase with the number of queries(can refer to https://materialize.com/blog/why-use-a-materialized-view/). Comparing with offload to real-time OLAP system.

## Conclusion

- use RW as a coprocessor to offload the analytics on RW, But the analysis results, in the RisingWave, were split from the original PG data. The results of the analysis can be served in two ways, by querying from RisingWave, or by querying from the original database portal, as will be described in the following two articles
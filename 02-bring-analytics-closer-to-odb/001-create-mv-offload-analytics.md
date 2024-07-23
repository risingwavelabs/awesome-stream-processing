# Create materialized views to offload predefined analytics

## Prerequisites

To execute this demo, the following systems must be installed:
 - A RisingWave instance 
 - A PostgreSQL database

To learn how to install the listed requirements, see the related sections under [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md).

Additionally, RisingWave must be configured to read data from a PostgreSQL table. To set up the PostgreSQL table and RisingWave table, follow the instructions outlined in [Ingest data from PostgreSQL CDC into RisingWave](/00-get-started/02-ingest-pg-cdc.md).

## Create and update a materialized view

Next, you will create a materialized view based on the CDC table, `pg_users`, created in Ingest data from PostgreSQL CDC into RisingWave. The materialized view `over21` will filter for all users who are at least 21 years old.

```sql
CREATE MATERIALIZED VIEW atleast21 AS
SELECT * FROM pg_users
WHERE age >= 21;
```

If you query from this table, it should return all three users.

```sql
SELECT * FROM atleast21;

 id | age |    name
----+-----+-------------
  1 |  25 | John Doe
  2 |  30 | Jane Smith
  3 |  22 | Bob Johnson
```

Next, you will update the `pg_users` table in PostgreSQL by inserting a few new users. In the terminal window running PostgreSQL, run the following query to add new users to the table.

```sql
INSERT INTO users (name, age) VALUES
    ('Aaron Reed', 18),
    ('Denice Tucker', 21),
    ('Paul Lewis', 35);
```

These new changes will be reflected in the `atleast21` materialized view in RisingWave. Check by querying from `atleast21` again. All users over the age of 21 should be listed.

```sql
 id | age |    name
----+-----+-------------
  1 |  25 | John Doe
  2 |  30 | Jane Smith
  3 |  22 | Bob Johnson
  5 |  21 | Denice Tucker
  6 |  35 | Paul Lewis
```

Creating materialized views allows you to save on valuable OLTP system resources. Increase the number of queries does not incur additional query costs as the materialized view is refreshed instantly when new data arrives in the system. 

## Conclusion

In this tutorial, RisingWave was used as a coprocessor to offload the analysis results in RisingWave. However, the results are split from the original data in PostgreSQL. There are two ways to serve the analysis results:
  - Querying from RisingWave
  - Querying from the original database portal.

In the following two sections, we will go over the each of these processes.

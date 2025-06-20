# Create materialized views to offload predefined analytics

## Prerequisites

To execute this demo, the following systems must be installed:
 - A RisingWave instance 
 - A PostgreSQL database

To learn how to install the listed requirements, see the related sections under [Install Kafka, PostgreSQL, and RisingWave](/00-get-started/00-install-kafka-pg-rw.md).

Additionally, RisingWave must be configured to read data from a PostgreSQL table. To set up the PostgreSQL and RisingWave table, follow the instructions outlined in [Ingest data from PostgreSQL CDC into RisingWave](/00-get-started/02-ingest-pg-cdc.md).

## Create and update a materialized view

Create a materialized view based on the CDC table, `pg_users`, created in Ingest data from PostgreSQL CDC into RisingWave. The materialized view `over21` will filter for all cities where users have an average age of at least 21 years.

```sql
CREATE MATERIALIZED VIEW atleast21 AS
SELECT city, avg(age) as avg_age FROM users
GROUP BY city
HAVING avg(age) >= 21;
```

If you query from this table, it should return all three cities.

```sql
SELECT * FROM atleast21;

     city      | avg_age 
---------------+---------
 Beijing       |   22
 San Francisco |   25
 New York      |   30
```

Next, in the window running PostgreSQL, run the following query to update the table by adding new users.

```sql
INSERT INTO users (name, age, city) VALUES
    (4, 'Aaron Reed', 18, 'San Francisco'),
    (5, 'Denice Tucker', 21, 'Beijing'),
    (6, 'Paul Lewis', 35, 'New York');
```

These new changes will be reflected in the `atleast21` materialized view in RisingWave. Check by querying from `atleast21` again. The average age of each city should be updated.

```sql
SELECT * FROM atleast21;

     city      | avg_age 
---------------+---------
 Beijing       |   21.50
 San Francisco |   21.50
 New York      |   32.50
```

Creating materialized views allows you to save on valuable OLTP system resources. Increasing the number of queries does not incur additional query costs as the materialized view is refreshed instantly when new data arrives in the system. 

## Conclusion

In this tutorial, RisingWave was used as a coprocessor to offload the analysis results. However, the results are split from the original data in PostgreSQL. There are two ways to serve the analysis results:
  - Querying from RisingWave.
  - Querying from the original database portal.

In the following two sections, we will go over the each of these processes.

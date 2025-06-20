# Ingest data from PostgreSQL CDC into RisingWave

Now let us use RisingWave to consume and analyze data from PostgreSQL. CDC (change data capture) refers to the process of identifying and capturing data changes in a database and delivering the changes to another service in real time. In this case, this means that any changes made in the PostgreSQL database will be reflected automatically in RisingWave.

If you need help installing these systems, refer to [Install Kafka, PostgreSQL, and RisingWave](00-install-kafka-pg-rw.md).

## Create a table in PostgreSQL

First, ensure you have downloaded and started the PostgreSQL server. For more information, check the [installation guide for PostgreSQL](00-install-kafka-pg-rw.md#install-postgresql).

Next, create a table and populate it with some data in PostgreSQL. The following creates a table `users` that has the columns `id`, `name`, `age`, and `city`.

```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    age INT,
    city VARCHAR
);
```

Insert some data into the table.

```sql
INSERT INTO users (name, age, city) VALUES
    ('John Doe', 25, 'San Francisco'),
    ('Jane Smith', 30, 'New York'),
    ('Bob Johnson', 22, 'Beijing');

-- optional: Have a look at the inserted users
select * from users;
```

## Use RisingWave to process the data

Now that PostgreSQL is set up, we can move over to RisingWave to ingest CDC data from PostgreSQL. Ensure that you have RisingWave up and running. For more information, check the [installation guide for RisingWave](00-install-kafka-pg-rw.md#install-risingwave).

To read CDC data from the table we just created, use the following SQL queries. First, create a connection to the PostgreSQL database using the `CREATE SOURCE` command. Next, use the `CREATE TABLE` command to create a table in RisingWave that ingests CDC data from a specific PostgreSQL table. If you created your table in a different database and schema, remember to adjust the parameter values.

```sql
CREATE SOURCE pg_mydb WITH (
    connector = 'postgres-cdc',
    hostname = 'localhost',
    port = '5432',
    username = '<USERNAME>',
    password = '<PASSWORD>',
    database.name = 'public'
);

CREATE TABLE pg_users (
    id integer,
    age integer,
    name varchar,
    city varchar
    PRIMARY KEY (id)
) FROM pg_mydb TABLE 'public.users';
```

As an example, for the [newly created user](00-install-kafka-pg-rw.md#optional-create-a-database-user) `rw` with password as `abc123`, run the following SQL.
```sql
CREATE SOURCE pg_mydb WITH (
    connector = 'postgres-cdc',
    hostname = 'localhost',
    port = '5432',
    username = 'rw',
    password = 'abc123',
    database.name = 'postgres'
);

CREATE TABLE pg_users (
    id integer,
    age integer,
    name varchar,
    city varchar
    PRIMARY KEY (id)
) FROM pg_mydb TABLE 'public.users';
```

Now you can query from the table to see the data, which should be the same as the PostgreSQL table.

```sql
SELECT * FROM pg_users;
```

The results will look like the following. Note that the rows do not necessarily follow this order.

```terminal
 id | age |    name     |     City
----+-----+-------------+---------------
  1 |  25 | John Doe    | San Francisco
  2 |  30 | Jane Smith  | New York
  3 |  22 | Bob Johnson | Beijing
(3 rows)
```

Any updates made to the `users` table in PostgreSQL will automatically be reflected in the `pg_users` table in RisingWave. To test this, go to the PostgreSQL database, insert some data, and query from the `pg_users` table again in RisingWave.

To learn more about how to consume data from PostgreSQL, see [Ingest data from PostgreSQL CDC](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/) from the official documentation.

## Optional: Clean up resources
To clean up the resources created in this section, follow the steps described below.

First, delete the created table in RisingWave.

```sql
DROP TABLE IF EXISTS pg_users;
```

Next, delete the table in PostgreSQL.

```sql
DROP TABLE IF EXISTS users;
```

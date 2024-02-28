# Ingest data from PostgreSQL CDC into RisingWave

Now that you have the necessary systems installed for stream processing, let us use RisingWave to consume and analyze data from PostgreSQL. CDC (change data capture) refers to the process of identifying and capturing data changes in a database and delivering the changes to another service in real time. In this case, this means that any changes made in the PostgreSQL database will be reflected automatically in RisingWave.

If you need help installing these systems, refer to [Install Kafka, RisingWave, and PostgreSQL](00-install-rw-kafka-pg.md).

## Set up PostgreSQL

Once you have the PostgreSQL server installed, connect to a database. By default, we will be running queries in the `public` schema under the `postgres` database. The default port is `5432` and the user is `postgres`. You can connect to a database by starting the psql terminal or by running the following line of code in a terminal window.

```terminal
psql -h localhost -p 5432 -d postgres -U postgres
```

> NOTE: If you are prompted for a password when running the `psql` command above, but you have not yet specified any password after installing PostgreSQL, check in the `pg_hba.conf` file (normally located as `/etc/postgresql/16/main/pg_hba.conf`) whether the default authentication method for the local connections is `trust`:
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
...
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
```

If not, modify the `METHOD` to `trust` and restart the postgres server by running `sudo service postgresql restart`.

Now you should be able to connect to the database without specifying any password. You may assign a password to the default user, or [create a new user](#optional-create-a-database-user) with your specified password.

After configuring a password for the user, recover the authentication method to the original value. Now you can run the aforementioned `psql` command again with the configured password.

### Configure the environment

Before RisingWave ingests data from PostgreSQL, we need to change the `wal_level` parameter to be `logical`.

To check the `wal_level`, use the following statement.

```sql
SHOW wal_level;
```

If it is already `logical`, skip to the next section. To change the value of the parameter, run the following statement.

```sql
ALTER SYSTEM SET wal_level = logical;
```

To save this change, close the terminal window with `\q` and restart the PostgreSQL instance. Then, run the following line of code to restart PostgreSQL. 

```terminal
sudo service postgresql restart
```

When you check the `wal_level` again, it should be `logical`.

### Optional: Create a database user

You can optionally create another database user for security and access control. This helps to limit which databases, schemas, and tables the user has control over. 

The following line of code creates a user `rw` with a password and the attributes `login` and `createdb`.

```sql
CREATE USER rw WITH PASSWORD 'abc123' REPLICATION LOGIN CREATEDB;
```

Next, grant the user with following privileges so we can access the desired PostgreSQL data from RisingWave. Fill in the database name accordingly based on where your data is located.

```sql
GRANT CONNECT ON DATABASE <database_name> TO <username>;
GRANT USAGE ON SCHEMA <schema_name> TO <username>;
GRANT SELECT ON ALL TABLES IN SCHEMA <schema_name> TO <username>;
GRANT CREATE ON SCHEMA <schema_name> TO <username>;
```

As an example, you may specify for our default settings as follows.
```sql
GRANT CONNECT ON DATABASE postgres TO rw;
GRANT USAGE ON SCHEMA public TO rw;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rw;
GRANT CREATE ON SCHEMA public TO rw;
```

To connect using the newly created user, run the following line of code.
```terminal
PGPASSWORD="abc123" psql -h localhost -p 5432 -d postgres -U rw
```

### Create a table in PostgreSQL

Next, create a table and populate it with some data in PostgreSQL.

The following creates a table `users` that has the columns `id`, `name`, and `age`.

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    age INT
);
```

Insert some data into the table.

```sql
INSERT INTO users (name, age) VALUES
    ('John Doe', 25),
    ('Jane Smith', 30),
    ('Bob Johnson', 22);
```

## Set up RisingWave

Now that PostgreSQL is set up, we can move over to RisingWave to ingest CDC data from PostgreSQL. Make sure that you have started RisingWave.

```terminal
./risingwave
```

In another terminal, connect to your RisingWave.

```terminal
psql -h localhost -p 4566 -d dev -U root
```

To read CDC data from the table we just created, use the following SQL query. We create a table `pg_users` in RisingWave that reads data from the `users` table created in PostgreSQL. Remember to fill in the username and password accordingly. If you created your table in a different database and schema, remember to adjust the parameter values.

```sql
CREATE TABLE pg_users (
    id integer,
    age integer,
    name varchar,
    PRIMARY KEY (id)
) WITH (
    connector = 'postgres-cdc',
    hostname = 'localhost',
    port = '5432',
    username = '<USERNAME>',
    password = '<PASSWORD>',
    database.name = 'postgres',
    schema.name = 'public',
    table.name = 'users'
);
```

As an example, for the [newly created user](#optional-create-a-database-user) `rw` with password as `abc123`, run the following SQL.
```sql
CREATE TABLE pg_users (
    id integer,
    age integer,
    name varchar,
    PRIMARY KEY (id)
) WITH (
    connector = 'postgres-cdc',
    hostname = 'localhost',
    port = '5432',
    username = 'rw',
    password = 'abc123',
    database.name = 'postgres',
    schema.name = 'public',
    table.name = 'users'
);
```

Now you can query from the table to see the data, which should be the same as the PostgreSQL table.

```sql
SELECT * FROM pg_users;
```

The results will look like the following.

```terminal
 id | age |    name     
----+-----+-------------
  1 |  25 | John Doe
  2 |  30 | Jane Smith
  3 |  22 | Bob Johnson
(3 rows)
```

Any updates made to the `users` table in PostgreSQL will automatically be reflected in the `pg_users` table in RisingWave. You can test this by going to the PostgreSQL database, inserting some data, and querying from the `pg_users` table again in RisingWave.

For more information, check [Ingest data from PostgreSQL CDC](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/) from the official documentation.

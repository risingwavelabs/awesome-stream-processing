# Install Kafka, PostgreSQL, and RisingWave

If you do not have experience with or have not installed Kafka, PostgreSQL, or RisingWave, follow along to learn how to set up these systems.

## Prerequisite: Install Java

As a kind reminder, both RisingWave and Kafka require Java in the environment, so make sure you have set up Java in advance. As an example, in Ubuntu you can install by running the following line of code.
```terminal
sudo apt-get install default-jre
```

You can verify the installation using the following line of code.
```terminal
java -version
```
The expected output will be the detailed version of the JRE and JVM.

## Install Kafka

Apache Kafka is an open-source distributed event streaming platform for building event-driven architectures, enabling you to retrieve and process data in real time. 

To install and run the self-hosted version of Kafka, follow steps outlined in this [Apache Kafka quickstart](https://kafka.apache.org/quickstart). You will have a good handle on how to install Kafka, start the environment, and create a topic where you can write/read events to/from.

## Install PostgreSQL

PostgreSQL is a relational database management system, allowing you to store and manage your data.

To use RisingWave and ingest CDC data from PostgreSQL databases, you will need to install the PostgreSQL server. To learn about the different packages and installers for various platforms, see [PostgreSQL Downloads](https://www.postgresql.org/download/).

### Connect to a database in the local PostgreSQL server 

Once you have the PostgreSQL server installed, connect to a database. By default, we will be running queries in the `public` schema under the `postgres` database. The default port is `5432` and the user is `postgres`. You can connect to a database by starting the `psql` terminal or by running the following line of code in a terminal window.

```terminal
psql -h localhost -p 5432 -d postgres -U postgres
```

> NOTE: If you are prompted for a password when running the `psql` command above, but you have not yet specified any password after installing PostgreSQL, check in the `pg_hba.conf` file (normally located as `/etc/postgresql/16/main/pg_hba.conf` in Ubuntu) whether the default authentication method for the local connections is `trust`:
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
...
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
```

If not, modify the `METHOD` to `trust` and restart the postgres server by running `sudo service postgresql restart`.

Now you should be able to connect to the database without specifying any password. You may assign a password to the default user, or to a [newly created user](#optional-create-a-database-user).

After configuring a password for the user, recover the authentication method to the original value. Now you should be able to run the aforementioned `psql` command again with the configured password.

### Configure PostgreSQL CDC

To allow stream processing systems like RisingWave to ingest data from PostgreSQL CDC (Change Data Capture), we need to change the `wal_level` parameter to be `logical`.

To check the `wal_level`, use the following statement.

```sql
SHOW wal_level;
```

If it is already `logical`, skip to the next section. To change the value of the parameter, run the following statement.

```sql
ALTER SYSTEM SET wal_level = logical;
```

To save this change, close the terminal window with `\q` and restart the postgres server by running `sudo service postgresql restart`.

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

## Install RisingWave

RisingWave is an open-source distributed SQL streaming database licensed under the Apache 2.0 license. It utilizes a PostgreSQL-compatible interface, allowing users to perform distributed stream processing in the same way as operating a PostgreSQL database.

You can install RisingWave using `curl`.

```terminal
curl https://risingwave.com/sh | sh
```

Next, start all RisingWave services by running the executable.

```terminal
./risingwave
```

In another terminal, run the following code to connect to RisingWave.

```terminal
psql -h localhost -p 4566 -d dev -U root
```

You can now start writing SQL queries to process streaming data. 

If you would like to explore other ways of installing RisingWave, see the [Quick start](https://docs.risingwave.com/docs/current/get-started/) guide.


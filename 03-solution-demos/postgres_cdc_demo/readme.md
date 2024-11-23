# Continuous E-Commerce Data Pipeline with PostgreSQL CDC and RisingWave

This demo delves into an e-commerce scenario that leverages PostgreSQL, CDC, and RisingWave to establish a real-time data processing pipeline. PostgreSQL serves as the repository for transactional data, while CDC captures and tracks database changes for efficient updates. RisingWave, a streaming database compatible with PostgreSQL, empowers real-time insights through the use of SQL. By adopting this architecture, an e-commerce company can achieve responsiveness and adaptability to dynamic market conditions. It empowers businesses with timely insights and informed decision-making capabilities. With PostgreSQL, CDC, and RisingWave working together, organizations can build a data pipeline that supports their e-commerce operations effectively.

![1](https://github.com/user-attachments/assets/e7f59bee-9d7f-487a-ad62-5b5a6d6bfd54)
*Continuous E-Commerce Data Pipeline with PostgreSQL CDC and RisingWave.*

## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launching the Demo Cluster

Follow these steps to enable Change Data Capture (CDC) in PostgreSQL, configure settings, and set up tables:

1. **Install PostgreSQL:** Download and install [PostgreSQL](https://www.postgresql.org/download/), ensuring it's available on your system.
2. **Create Tables:** Use the PostgreSQL client or command line to set up tables for an e-commerce scenario:
    - **users**: `user_id`, `username`, `email`, `registration_date`, `last_login`, `address`
    - **products**: `product_id`, `product_name`, `brand`, `category`, `price`, `stock_quantity`
    - **sales**: `sale_id`, `user_id` (FK to `users`), `product_id` (FK to `products`), `sale_date`, `quantity`, `total_price`
3. **Enable CDC:** Change the Write-Ahead Log (WAL) level to `logical` by running:
    
    ```sql
    ALTER SYSTEM SET wal_level = logical;
    ```
    
    Restart PostgreSQL after this change to apply it.
    
4. **Update Configuration Files:**
    - In `postgresql.conf`, set:
        
        ```
        listen_addresses = '*'
        ```
        
    - In `pg_hba.conf`, add:
        
        ```
        host    all             all             0.0.0.0/0               md5
        host    replication     all             0.0.0.0/0               scram-sha-256
        ```
        
5. **Restart PostgreSQL:** Apply changes to allow RisingWave to read CDC data using logical replication.

For further details, refer to the [RisingWave PostgreSQL CDC documentation](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/).

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/postgres_cdc_demo` directory, and start the demo using Docker Compose.
    
    ```bash
    cd awesome-stream-processing/04-solution-demos/postgres_cdc_demo
    docker compose up -d
    ```
    
    This setup will launch the essential RisingWave components (frontend node, compute node, and metadata node) and MinIO for storage. The data from an e-commerce site will be continuously sent to PostgreSQL tables, making it accessible through a source in RisingWave for further processing and analysis.
    
3. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views.
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    ```
    

Create a source in RisingWave using `create_source.sql`. Then, define tables with `create_table.sql` and materialized views with `create_mv.sql` to enable real-time analytics on data from PostgreSQL tables, utilizing time window functions and aggregations.

For more information, refer to [Continuous E-Commerce Data Pipeline with PostgreSQL CDC and RisingWave Cloud](https://risingwave.com/blog/continuous-e-commerce-data-pipeline-with-postgresql-cdc-and-risingwave-cloud/).

# Wikipedia monitoring demo

In this demo, we set up a real-time Wikipedia edits monitoring system using RisingWave and Kafka. We use the Wikiepdia API to capture data on contributor information. This data is written to a Kafka topic. In RisingWave, we will ingest, process, and transform this data using SQL queries. 

## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launch the Demo Cluster

This demo uses the Wikipedia API to obtain real-time data on edits made to Wikipedia articles.

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/wikipedia-monitoring` directory, and start the demo using Docker Compose.
    
    ```bash
    cd awesome-stream-processing/04-solution-demos/wikipedia-monitoring
    docker compose up -d
    
    ```
    
    This will initiate the standalone mode of RisingWave, a Kafka instance, and Zookeeper. Data from the Wikipedia API will automatically be sent to a Kafka topic.  
    
    > Note: Kafka is exposed on `kafka:9092` for internal applications and on `localhost:29092` for local applications. The corresponding source topic is created automatically.
    > 
3. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views. 
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    ```

    For SQL queries on ingesting and processing data, see [create-source.sql](/04-solution-demos/wikipedia_monitoring/create_source.sql) and [create-mv.sql](/04-solution-demos/wikipedia_monitoring/create_mv.sql).

    
# Flight tracking demo

In this demo, we set up a real-time flight tracking system using [RisingWave](https://risingwave.com/), Kafka, and Metabase. We leverage the [Aviationstack API](https://aviationstack.com/) to get real-time flight data, and then transmit this data into a Kafka topic. These streams are then ingested into RisingWave using a Kafka connector, enabling us to create materialized views (MVs) for thorough flight data analysis. MVs maintain the latest results and are instantly queryable. We also use Metabase to create charts, tables, and a unified dashboard for real-time flight tracking.

![Untitled](https://github.com/user-attachments/assets/3b4d4e4f-758a-46f5-95d4-e6159204cc80)


## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launch the Demo Cluster

The demo uses the Aviationstack API to fetch real-time flight data, which is then streamed into Kafka once the cluster starts.

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/flight-tracking` directory, and start the demo using Docker Compose.
    
    ```bash
    cd awesome-stream-processing/04-solution-demos/flight-tracking
    docker compose up -d
    
    ```
    
    This will initiate the standalone mode of RisingWave. The Aviationstack API will begin fetching real-time flight data and send it to a Kafka topic, where RisingWave ingests and processes it into materialized views, stored in the embedded SQLite database.
    
    > Note: Kafka is exposed on `kafka:9092` for internal applications and on `localhost:29092` for local applications. The corresponding source topic is created automatically.
    > 
3. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views.
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    
    ```

### Connect RisingWave to Metabase

Since RisingWave is PostgreSQL-compatible, you can connect it to Metabase as a data source for building visualizations. This integration allows you to create real-time dashboards on streaming data using RisingWave tables and materialized views. You can access Metabase at `http://localhost:3000` in this demo.

For more details, refer to [Real-time flight tracking with Redpanda, RisingWave, and Metabase](https://risingwave.com/blog/real-time-flight-tracking-with-redpanda-risingwave-and-metabase/).


# Automating Airline Operations with Solace and RisingWave

In this demo, we explore two scenarios that illustrate the benefits of integrating Solace and RisingWave: flight check-in notifications and catering management alerts for meal shortages. We will delve into the technical details of ingesting data from the Departure Control System (DCS) and Catering Management System (CMS) into the Solace PubSub+ event broker, and then processing it in RisingWave to create source tables and materialized views for continuous analytics. We will also cover how notifications are sent to Solace topics via the RisingWave sink connector for downstream applications, and how data is sent to Grafana for real-time dashboards, supporting informed decisions, operational efficiency, and an enhanced customer experience.

![1](https://github.com/user-attachments/assets/1a38af23-eafe-4ebd-8ab7-5bc27dd95583)

## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launching the Demo Cluster

The Solace PubSub+ broker is set up using Docker Compose and is configured to receive message streams from both the DCS and CMS systems. Using the RisingWave MQTT source connector, we can read these data streams from Solace topics. Additionally, with the RisingWave MQTT sink connector, we can send the analyzed data back to Solace topics. This enables downstream applications and services to access these results from RisingWave and trigger the required notifications.

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/automating-airline-operations` directory, and start the demo using Docker Compose.

```bash
cd awesome-stream-processing/04-solution-demos/automating_airline_operations
docker compose up -d
```

This setup will launch the RisingWave components (frontend node, compute node, and metadata node), along with MinIO for storage. Data from random data generators simulating the Departure Control System (DCS) and Catering Management System (CMS) will be continuously sent to different Solace topics, making it accessible through source tables created using MQTT connectors in RisingWave for further processing and analysis.

1. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views.
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    ```
    

 

Create a source table in RisingWave using `create_table.sql`. Then, create materialized views with `create_mv.sql` to enable real-time analytics from Solace topics using RisingWave's built-in functions. After creating the necessary materialized views for both scenarios—**notifying passengers precisely 48 hours before their flights' departure that online check-in is open** and **notifying the Catering Management System (CMS) when there aren’t enough meals for passengers based on check-ins**—create sinks using `create_sink.sql` with the MQTT sink connector to send data to the corresponding Solace topics.

## Connect RisingWave to Grafana for visualization

The Docker Compose setup includes a Grafana instance. To access it, open your browser and navigate to [http://localhost:3000](http://localhost:3000/). Log in with the default credentials (`admin/admin`) unless these have been changed in your configuration.

### Configuring RisingWave as a Data Source in Grafana

To use RisingWave as a data source in Grafana for creating visualizations and dashboards, follow the steps outlined in the [Grafana Integration Guide](https://docs.risingwave.com/docs/current/grafana-integration/). During the configuration, set the host URL to `risingwave-standalone:4566` to connect to RisingWave in this demo environment.

### Visualizations and Dashboards

Once the connection is established, you can leverage materialized views in RisingWave as tables to design charts and build dashboards for monitoring systems like an online check-in message system and a catering management system.

One table chart displays passengers who have opted in for notifications and have flights departing soon. The chart includes details such as `flight_id`, `passenger_ref_number`, `flight_number`, `carrier_code`, `departure_time`, and `contact_info`.

It highlights passengers with flights departing within 48 hours, signaling that check-in is open.

![2](https://github.com/user-attachments/assets/8231c9ef-b310-423d-9833-e5ecb493efd7)

This system, powered by Solace and RisingWave, ensures passengers receive timely, accurate notifications, improving both airline operational efficiency and customer satisfaction.

Another table chart highlights flights experiencing meal shortages. This chart displays details such as `flight_id`, `flight_number`, `class`, `checked_in_passengers`, `available_meals`, and `meal_status`.

Only flights where the `meal_status` is marked as **Meal Shortage** are shown, offering a concise view of flights requiring immediate meal restocking.

![3](https://github.com/user-attachments/assets/14d2c5d4-4418-46a0-b966-0991617216cf)

By integrating RisingWave with Solace, the system delivers real-time alerts to the CMS, enabling proactive identification and resolution of meal shortages. This demonstrates how RisingWave enhances operational efficiency and improves service quality.

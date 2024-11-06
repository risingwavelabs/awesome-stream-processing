# Real-Time Monitoring, Predictive Maintenance, and Anomaly Detection with MQTT, RisingWave, and Grafana

In this demo, we develop a real-time monitoring, predictive maintenance, and anomaly detection system for PBL86-80 motors used in robotic solutions in manufacturing. This system collects data from the motors on a factory-floor, sends it to an MQTT broker running locally, and ingests it into RisingWave for advanced real-time analytics for monitoring, predictive maintenance and anomaly detection. Then, Grafana is used to create charts and real-time dashboard that monitors the factory shop floor.  

<img width="1213" alt="Frame 14" src="https://github.com/user-attachments/assets/dde9399b-8501-4530-8b69-5918b63a1952">

*Real-Time Monitoring, Predictive Maintenance, and Anomaly Detection with MQTT, RisingWave, and Grafana.*

## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launching the Demo Cluster

We are now ready to ingest shop-floor data from the factory floor into the MQTT broker using the Paho Python client as the cluster starts.

Here is a sample of the shop-floor data for electric motors in JSON format:

```json
{
  "machine_id": "machine_1",
  "winding_temperature": 80,
  "ambient_temperature": 40,
  "vibration_level": 1.97,
  "current_draw": 14.43,
  "voltage_level": 50.37,
  "nominal_speed": 4207.69,
  "power_consumption": 646.32,
  "efficiency": 82.88,
  "ts": "2024-09-09 09:57:51"
}
```

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/iot_demo` directory, and start the demo using Docker Compose.
    
    ```bash
    cd awesome-stream-processing/04-solution-demos/iot_demo
    docker compose up -d
    ```
    
    This setup will launch the essential RisingWave components (frontend node, compute node, and metadata node), along with MinIO for storage. IoT devices on the factory floor will transmit machine data to an MQTT topic, which RisingWave ingests and processes into materialized views stored in MinIO.
    
3. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views.
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    ```
    

## Connect RisingWave to Grafana for visualization

The Docker Compose setup includes a Grafana instance. Open your browser to [http://localhost:3000](http://localhost:3000/), and log in with the default credentials (admin/admin) unless otherwise configured.

To utilize RisingWave as a data source in Grafana and create visualizations and dashboards, follow the instructions provided in [Configure Grafana to read data from RisingWave](https://docs.risingwave.com/docs/current/grafana-integration/).

Once the connection between RisingWave and Grafana is established, you can incorporate materialized views from RisingWave as tables to design charts and build a comprehensive dashboard for real-time monitoring of factory floor, predictive maintenance, and anomaly detection.

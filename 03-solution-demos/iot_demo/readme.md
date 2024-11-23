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

To utilize RisingWave as a data source in Grafana and create visualizations and dashboards, follow the instructions provided in [Configure Grafana to read data from RisingWave](https://docs.risingwave.com/docs/current/grafana-integration/). Set the host URL as `risingwave-standalone:4566` to connect to RisingWave in this demo.

Once the connection between RisingWave and Grafana is established, you can incorporate materialized views from RisingWave as tables to design charts and build a comprehensive dashboard for real-time monitoring of the factory floor, predictive maintenance, and anomaly detection.

1. **Table of Sensor Readings and Operational Metrics**: This table, sourced from `shop_floor_machine_data`, shows machine performance metrics with each record detailing a machine’s status at a specific time.
![1](https://github.com/user-attachments/assets/d7c06048-1e49-4ca7-a051-76a347bab17b)

2. **Anomaly Alerts Chart**: This chart from `anomalies_mv` displays alerts (e.g., “Anomalous Vibration Level,” “Rising Power Consumption”) triggered by threshold deviations, aiding real-time anomaly detection.
![2](https://github.com/user-attachments/assets/d6dcb1f6-b7fe-4f9a-8649-857b7c7b9c23)

3. **Maintenance Alerts Chart**: This chart, based on `maintenance_mv`, highlights deviations from historical averages, triggering alerts (e.g., "Potential Overheating") to support proactive maintenance.
![3](https://github.com/user-attachments/assets/0d107898-46d1-4a46-a4d6-7ea6c0bc95b8)

4. **Winding Temperature Chart**: This chart from `shop_floor_machine_data` tracks winding temperatures, highlighting data points in red for readings above 81°C to signal potential overheating.
![4](https://github.com/user-attachments/assets/463212ad-ef16-4023-99ec-427319660e89)

5. **Vibration Levels Chart**: This chart from `shop_floor_machine_data` shows vibration levels, flagging readings above 2.05 as indicators of potential mechanical issues.
![5](https://github.com/user-attachments/assets/a006456b-23d2-4dd4-88fe-82b5ac787bd1)

6. **Ambient Temperature Distribution Pie Chart**: Using data from `shop_floor_machine_data`, this chart represents the distribution of ambient temperatures on the shop floor.
![6](https://github.com/user-attachments/assets/c8546ec4-be04-4336-b275-b648d1352f82)

7. **Speed and Power Consumption Chart**: This bar chart from `shop_floor_machine_data` shows nominal speed and power consumption, with a red line indicating a threshold of 4210 for comparison.
![7](https://github.com/user-attachments/assets/90d4dfda-1006-42e2-8819-5cc013ca1c90)

8. **Efficiency Chart**: Based on `shop_floor_machine_data`, this chart displays machine efficiency, with red highlights for data points below 80 to flag underperformance.
![8](https://github.com/user-attachments/assets/85f96203-4c8a-46f9-8241-d7c57887c594)

9. **Real-time Unified Dashboard**: This comprehensive dashboard monitors shop floor operations, displaying alerts for predictive maintenance and anomaly detection, supporting proactive equipment management.
![9](https://github.com/user-attachments/assets/0e87b49e-97e0-42a3-90b1-93570a918270)

For more details, refer to [Real-Time Monitoring, Predictive Maintenance, and Anomaly Detection with EMQX, RisingWave, and Grafana](https://risingwave.com/blog/real-time-monitoring-predictive-maintenance-and-anomaly-detection-with-emqx-risingwave-and-grafana/).

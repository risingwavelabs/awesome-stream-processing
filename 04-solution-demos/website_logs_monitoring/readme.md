# Real-Time Website Logs Monitoring with Kafka, RisingWave, and Grafana

This demo presents a real-time website monitoring system using RisingWave, Kafka, and Grafana. Kafka streams website audit logs, which are ingested into RisingWave for continuous data analysis, enabling timely threat detection and real-time analytics. Grafana provides a unified dashboard displaying user activities, referrer analytics, status codes, and user security profiles, supporting efficient monitoring and automated threat responses.

## Prerequisites

Ensure you have the following installed:

- **[Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/):** Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- **[PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/):** This will allow you to connect to RisingWave for stream management and queries.

## Launching the Demo Cluster

Random website logs containing information about user activities, requests, and responses are generated and then sent to a Kafka topic, which is ingested into RisingWave for continuous analysis.

1. **Clone the Repository:** First, clone the [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing) repository.
    
    ```bash
    git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
    ```
    
2. **Start the Demo Cluster:** Navigate to the `04-solution-demos/website_logs_monitoring` directory, and start the demo using Docker Compose.
    
    ```bash
    cd awesome-stream-processing/04-solution-demos/website_logs_monitoring
    docker compose up -d
    ```
    
    This setup will launch the essential RisingWave components (frontend node, compute node, and metadata node), along with MinIO for storage. The data from a random data generator will be continuously sent to Kafka topic, making it accessible through a source in RisingWave for further processing and analysis.
    
3. **Connect to RisingWave:** Use `psql` to manage data streams and analyze data via materialized views.
    
    ```bash
    psql -h localhost -p 4566 -d dev -U root
    ```
    

Create a source in RisingWave using `create_source.sql`. Then, create materialized views with `create_mv.sql` to enable real-time analytics on website logs data from a Kafka topic, using time window functions and aggregations.

4. **Connect RisingWave to Grafana for visualization**

The Docker Compose setup includes a Grafana instance. Open your browser to [http://localhost:3000](http://localhost:3000/), and log in with the default credentials (admin/admin) unless otherwise configured.

To utilize RisingWave as a data source in Grafana and create visualizations and dashboards, follow the instructions provided in [Configure Grafana to read data from RisingWave](https://docs.risingwave.com/docs/current/grafana-integration/). Set the host URL as `risingwave-standalone:4566` to connect to RisingWave in this demo.

Once the connection between RisingWave and Grafana is established, you can use materialized views from RisingWave as tables to design charts and build a comprehensive dashboard for real-time website monitoring. 

This table is generated from the `website_logs_source` source.

<img width="946" alt="1" src="https://github.com/user-attachments/assets/cae34f64-70d1-4aa4-a6b6-cc63280f85e0">


This chart is generated from the `referrer_activity_summary` materialized view to summarize website activity based on referrers. 

<img width="940" alt="2" src="https://github.com/user-attachments/assets/8314e54e-c540-41f6-a5b1-d6cfc2d5ece0">


This chart is generated from a materialized view named `website_user_metrics` to provide aggregated statistics on user activity based on website logs. 

<img width="935" alt="3" src="https://github.com/user-attachments/assets/459ea44c-4815-43cc-981f-cec5967166b6">


This chart is generated from the `security_level_analysis_summary` materialized view  to analyze and summarize security levels within one-minute intervals in website logs.

<img width="935" alt="4" src="https://github.com/user-attachments/assets/a801073d-4f70-4dc3-b298-9c4eac2a85b1">


This chart is created on a materialized view `top_user_actions` to identify and rank the top five user actions based on their frequency within one-minute intervals of website logs.

<img width="934" alt="5" src="https://github.com/user-attachments/assets/83d09577-5cce-46eb-b856-8dc75bb6a144">


This chart is generated from the `status_code_analysis_summary`  materialized view to analyze and summarize the distribution of HTTP status codes over one-minute intervals in website logs.

<img width="930" alt="6" src="https://github.com/user-attachments/assets/a09aaebc-b1bb-4064-9f9b-336c61347093">


This dashboard provides real-time insights into website activity, including referrers, HTTP status codes, top user actions, and security levels. The combined charts offer a holistic view, enhancing threat detection and security monitoring.

<img width="955" alt="7" src="https://github.com/user-attachments/assets/c3e61f7e-7d84-47bf-a478-ddf628073c4f">


For more information, refer to [Real-Time Website Security Monitoring with WarpStream, RisingWave, and Grafana](https://risingwave.com/blog/real-time-website-security-monitoring-with-warpstream-risingwave-and-grafana/)

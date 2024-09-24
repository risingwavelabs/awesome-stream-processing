## Real-time energy grid monitoring 

In this demo, we use RisingWave to monitor an small energy grid in real-time. The data generator mimics the energy usage pattern for 20 households. Each household will consume energy and produce energy (such as through solar panels). We will use RisingWave to track the energy usage patterns for each household, as well as their monthly bills. 

This demo runs via Docker so install docker if you have not already done so. After pulling this directory onto your local device, navigate to this file and run docker compose up -d to start all services, which includes a Kafka instance, a Zookeeper, a data generator, a RisingWave instance, a PostgreSQL instance, and a Grafana instance. 

Once all the services are up and running (aside from the `postgres_prepare` instance), connect to RisingWave via `psql -h localhost -p 4566 -d dev -U root` from a terminal window. 

Run all queries included in the `create_source.md` and `create_mv.md` files.

Open the Grafana instance and navigate to the Grid Monitoring dashboard, which is already set up. If the graphs are not loading, refresh the queries.
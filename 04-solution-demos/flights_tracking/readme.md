# Flight tracking demo

In this demo, we build a real-time monitoring system of public aviation data. We will send real-time aviation data from an API to Kafka, process and analyze the data in RisingWave, and create visualizations in Metabase.

After pulling this directory onto your local device, navigate to this file and run `docker compose up -d` to start all the services. Install docker if you have not already done so. 

Under the Zookeeper and Metabase containers, adjust the specified platforms as needed based on your device.

Kafka is exposed on `kafka:9092` for applications running internally and `localhost:29092` for applications running on your local device. Corresponding source topic is created automatically. 

When connecting RisingWave to Metabase, use `risingwave` as the host address. Note that it takes a minute or so for Metabase to be up and running. Check the logs to keep track of its progress.



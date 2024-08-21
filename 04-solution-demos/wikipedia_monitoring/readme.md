# Wikipedia monitoring demo

After pulling this directory onto your local device, navigate to this file and run `docker compose up -d` to start all the services. Install docker if you have not already done so. 

Under the Zookeeper container, adjust the specified platforms as needed based on your device.

Kafka is exposed on `kafka:9092` for applications running internally and `localhost:29092` for applications running on your local device. Corresponding source topic is created automatically. 
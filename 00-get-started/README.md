# Get Started

The demos in this directory are designed to assist users in setting up their local environment and installing Kafka, PostgreSQL, and RisingWave. These are the three fundamental systems we will be using.

0. [Install Kafka, PostgreSQL, and RisingWave](00-install-kafka-pg-rw.md)

1. [Ingest data from Kafka into RisingWave](01-ingest-kafka-data.md)

2. [Ingest CDC (Change Data Capture) from PostgreSQL into RisingWave](02-ingest-pg-cdc.md)

3. [Integrate RisingWave with other platforms](https://github.com/risingwavelabs/risingwave/tree/main/integration_tests)
    * If you would like to test how RisingWave integrates with other messaging queues, databases, data lakes, and more, head over the `integration_tests` folder under the RisingWave repository. Docker Compose files have been set up for each integration, allowing you to easily test the workflow.
    * Simply pull the repository to your device, navigate to the integration you are interested in, and run `docker compose up -d` in a terminal window. 

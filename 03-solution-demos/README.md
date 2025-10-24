# Solution demonstrations

The demos in this directory aim to demonstrate how to build a streaming data pipeline for real-world industry applications. All demos can be run using Docker Compose for ease of setup and include detailed deployment instructions.

Here are the runnable demos so far:

* [Real-time energy grid monitoring](/03-solution-demos/energy_grid/readme.md): Monitor the energy consumption and production patterns of an energy grid in real-time using Kafka, PostgreSQL, RisingWave, and Grafana.

* [Real-time flight tracking system](/03-solution-demos/flights_tracking/readme.md): Keep track of live flight data from Aviationstack API using Kafka, RisingWave, and Metabase.

* [Real-time monitoring, predictive maintenance, and anomaly detection](/03-solution-demos/iot_demo/readme.md): Detect anomalies in real-time for PBL86-80 motors using MQTT, RisingWave, and Grafana.

* [Wikipedia edits monitoring system](/03-solution-demos/wikipedia_monitoring/readme.md): Track contributions made to Wikipedia pages in real time using the Wikipedia API, Kafka, and RisingWave.

* [Spoofing detection with actual Market data](/03-solution-demos/spoofing_detection_with_live_market_data/readme.md): Detect spoofing in trading events in real-time by leveraging RisingWave and real-time market data from [Databento](https://databento.com/). Detailed explanations can be found in [this blog post](https://risingwave.com/blog/spoofing-detection-databento-risingwave/).

* [Real-time PostgreSQL → Apache Iceberg CDC](/03-solution-demos/postgres_cdc_iceberg/readme.md): Stream PostgreSQL CDC into Apache Iceberg with RisingWave’s native connectors, query it through Spark, Trino, or Dremio, then loop the results back for a faster, simpler stack than Kafka and/or Flink.

* [Traffic flow monitoring and predication](/03-solution-demos/traffic_prediction): Detect traffic flow by ingesting car speed events in real-time, and predict the traffic flow based historical data and a ML model.

* [Real-time promotion rule engine](/03-solution-demos/promotion_rule_engine/): A real-time promotion rule engine on RisingWave + Kafka that matches member events to configurable rules, computes capped rewards, and exposes results and analytics views.

## Compare metrics

This demo aims to observe the performance metrics of RisingWave and Flink simultaneously. We will be using the same message queues for both demos and the same queries for a fair comparison.

Navigate to the `producer` and `flink` directories and read their respective readme files to learn how to run both docker compose projects. You should be able to run both docker compose projects simultaneously.

Be sure to install the Confluent library for Python if it's not already installed on your device. 

```terminal
pip install confluent_kafka
```

Note that the metrics between Flink and RisingWave aren't the same but they represent the same concepts. While the usage of Flink here to process streaming data may not be ideal, it is reflective of how a first-time user may approach this. It also allows for a clear side-by-side comparison of RisingWave and Flink. 
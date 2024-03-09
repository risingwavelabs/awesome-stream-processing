FROM flink:1.16.3-scala_2.12

# Download and copy both JAR files into the /opt/flink/lib directory
RUN wget -P /opt/flink/lib \
    https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.16.3/flink-sql-connector-kafka-1.16.3.jar && \
    wget -P /opt/flink/lib \
    https://repo.maven.apache.org/maven2/org/apache/flink/flink-metrics-prometheus/1.4.2/flink-metrics-prometheus-1.4.2.jar && \
    chown -R flink:flink /opt/flink/lib
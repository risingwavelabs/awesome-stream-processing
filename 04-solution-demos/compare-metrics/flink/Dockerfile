FROM flink:1.15.2-scala_2.12
RUN wget -P /opt/flink/lib https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.15.2/flink-sql-connector-kafka-1.15.2.jar
RUN chown -R flink:flink /opt/flink/lib
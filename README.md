
# :school: Awesome Stream Processing :school:

<div>
  <a
    href="https://go.risingwave.com/slack"
    target="_blank"
  >
    <img alt="Slack" src="https://badgen.net/badge/Slack/Join%20RisingWave/0abd59?icon=slack" />
  </a>
</div>


The term "stream processing" might sound intimidating to many people. We often hear statements like:

- "Stream processing is too difficult to learn and use!" 😱
- "Stream processing is very expensive!" 😱
- "I don’t see any business use cases for stream processing!" 😱

_**However, we believe this isn't true.**_ ❌


Streaming data is everywhere, generated from operational databases, messaging queues, IoT devices, and many other sources. People can leverage modern stream processing technology to easily address classic real-world problems, using SQL as the programming language.

In this repository, we provide a series of executable demos demonstrating how stream processing can be applied in practical scenarios:

0. [**Getting started ✅**](00-get-started/)
    * Install Kafka, PostgreSQL, and RisingWave, and run minimal toy examples on your device.
    * Integrate RisingWave with other data platforms.
1. [**Basic stream processing examples ✅**](01-basic-streaming-workflow)

    Learn the fundamentals of ingesting, processing, transforming, and offloading data from streaming systems.
    1. [**Querying and processing event streaming data**](/01-basic-streaming-workflow/01-query-process-streaming-data/) (👈 _**Kafka users, you may start here!**_ 💡)
      * Directly query data stored in event streaming systems (e.g., Kafka, Redpanda).
      * Continuously ingest and analyze data from event streaming systems.
    2. [**Bringing analytics closer to operational databases**](/01-basic-streaming-workflow/02-bring-analytics-closer-to-odb/) (👈 _**Postgres users, you may start here!**_ 💡)
      * Offload event-driven queries (e.g., materialized views and triggers) from operational databases (e.g., MySQL, PostgreSQL).
    3. [**Real-time ETL (Extract, Transform, Load)**](/01-basic-streaming-workflow/03-real-time-etl/)
      * Perform ETL continuously and incrementally.
2. [**Simple demonstrations ✅**](02-simple-demos/)
   * A collection of simple, self-contained demos showcasing how stream processing can be applied in specific industry use cases.
3. [**Solution demonstrations ✅**](03-solution-demos/)
   * A collection of comprehensive demos showcasing how to build a stream processing pipeline for real-world applications.
4. **RAG & Metrics Comparisons ✅**

- [**RisingWave RAG Demo**](04-rag-demo/)
    - Build a Retrieval-Augmented Generation system using RisingWave. The pipeline stores documentation chunks and their embeddings, retrieves the most similar documents for a user query, and calls an LLM to generate grounded answers.
- [**Compare Metrics (RisingWave vs. Flink)**](04-solution-demos/compare-metrics/)
    - Run the same workloads on both systems using the same message queues and queries to observe and compare performance metrics side by side.
5. [**Agent Demo ✅**](05-agent-demo/)
    - Use AI agents to analyze data ingested into RisingWave. This client app connects RisingWave’s MCP with Anthropic’s LLM to parse natural-language questions, discover relevant tables/schemas, call data tools, and iteratively return clean results (e.g., formatted tables).
6. [**Data Engineering Agent Swarm ✅**](06-data-agent/)
    - A multi-agent system for common data engineering tasks with RisingWave and Kafka integration. Includes a planner that delegates to specialized agents for database ops, stream processing, and pipeline orchestration; supports automatic schema inference and an interactive chat loop.
7. [**RisingWave + Apache Iceberg — End-to-End Streaming Lakehouse Demos ✅**](07-iceberg-demos/)
    - Self-contained pipelines (Docker Compose + SQL) showing RisingWave writing to Apache Iceberg and querying with external engines.
        - [**streaming_iceberg_quickstart**](07-iceberg-demos/streaming_iceberg_quickstart/) — Build your first streaming Iceberg table with RisingWave (self-hosted catalog) and query with Spark.
        - [**postgres_to_rw_iceberg_spark**](07-iceberg-demos/postgres_to_rw_iceberg_spark/) — PostgreSQL CDC → RisingWave → Iceberg → Spark using the Iceberg Table Engine and hosted catalog.
        - [**mongodb_to_rw_iceberg_spark**](07-iceberg-demos/mongodb_to_rw_iceberg_spark/) — MongoDB change streams → RisingWave → Iceberg → Spark with JSON→typed projection.
        - [**mysql_to_rw_iceberg_spark**](07-iceberg-demos/mysql_to_rw_iceberg_spark/) — MySQL binlog CDC → RisingWave → Iceberg → Spark end-to-end.
        - [**risingwave_lakekeeper_iceberg_duckdb**](07-iceberg-demos/risingwave_lakekeeper_iceberg_duckdb/) — RisingWave → Lakekeeper (REST) → Iceberg → DuckDB with upsert streaming.
        - [**risingwave_s3tables_iceberg_duckdb**](07-iceberg-demos/risingwave_s3tables_iceberg_duckdb/) — Use AWS S3 Tables catalog to stream from RisingWave to Iceberg and query with DuckDB (no local catalog containers).
        - [**logistics_multiway_streaming_join_iceberg**](07-iceberg-demos/logistics_multiway_streaming_join_iceberg/) — Seven-topic logistics streaming join in RisingWave writing to Iceberg (hosted catalog), real-time analysis, then query with Spark.
        - [**risingwave_lakekeeper_iceberg_clickhouse**](07-iceberg-demos/risingwave_lakekeeper_iceberg_clickhouse/) — RisingWave → Lakekeeper (REST) → Iceberg → ClickHouse with streaming writes and shared REST catalog.

We use [RisingWave](https://github.com/risingwavelabs/risingwave) as the default stream processing system to run these demos. We also assume that you have [Kafka](https://kafka.apache.org/) and/or [PostgreSQL](https://www.postgresql.org/) installed and possess basic knowledge of how to use these systems. **These demos have been verified on Ubuntu and Mac.**

_**All you need is a laptop**_ 💻 - _**no cluster is required.**_

Any comments are welcome. Happy streaming!

Join our [Slack community](https://www.risingwave.com/slack) to engage in discussions with thousands of stream processing enthusiasts!

# Bringing analytics closer to operational databases

Operational databases are critical for business operations, but they are also best suited for simple queries. Running complex queries can hinder critical processes. The solution is offloading. Moving the queries to another platform frees up resources for the operational database.

RisingWave can easily ingest data from operational databases and perform computation-heavy tasks. Using pre-defined computations provided, RisingWave completes the computation when the data is written rather than at the time of querying. This allows for the reuse of repeated computation between multiple queries.

The demos included in this directory aim to show how RisingWave can be used in stream processing to bring your analytics closer to your operational database.

1. [Create materialized views to offload predefined analytics](./001-create-mv-offload-analytics.md)

2. [Query through RisingWave](./002-query-through-risingwave.md)

3. [Query the results from the original database](./003-query-from-odb.md)

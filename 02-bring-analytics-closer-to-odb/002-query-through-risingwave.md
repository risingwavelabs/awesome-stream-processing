# Query through Risingwave

RisingWave is designed for online serving and supports online data serving at high concurrency and low latency. Also, RIsingWave has lots of optimization, including many traditional database optimizations, such as lookup join with the help of indexes, etc. So it is ok to use Risingwave the serve online application. In this case, RIsingWave is like a read-only instance of the operational database that focuses on handling predefined analysis requests and read requests.

## Create an index

Querying from a growing materialized view can get slower over time. To accelerate the query, we can create an index on the column we want to query on.


- create an index on the materialized view and give a query can accelerated by it.
- (operational), explain the consistency of mv’s result here?
- deploy serving node(we can not demo it with stand alone but worth mentioning that)
    - https://docs.risingwave.com/docs/current/performance-faq/#when-to-choose-to-deploy-a-dedicated-batch-serving-cluster
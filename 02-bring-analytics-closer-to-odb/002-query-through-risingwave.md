# Query through RisingWave

RisingWave is designed for online serving and supports online data serving at high concurrency and low latency. Also, RisingWave has lots of optimization, including many traditional database optimizations, such as lookup join with the help of indexes, etc. So it is ok to use RisingWave the serve online application. In this case, RisingWave is like a read-only instance of the operational database that focuses on handling predefined analysis requests and read requests.

## Create an index

Querying from a growing materialized view can get slower over time. To accelerate the query, create an index on the column being queried from.

Continuing with the `users` table described in [Create materialized views to offload predefined analytics](/02-bring-analytics-closer-to-odb/001-create-mv-offload-analytics.md), you can build an index on the `age` column. This will speed up the query of fetching a user by their age. 

```sql
CREATE INDEX idx_age ON users(age);

SELECT * FROM users WHERE age > 18;
```

To learn more about the `CREATE INDEX` command, see the [official documentation](https://docs.risingwave.com/docs/current/sql-create-index/#how-to-decide-the-index-distribution-key).

Note that materialized views in RisingWave are consistent. Even when using different refresh strategies, the correct results will be provided across multiple materialized views. 

## Optional: Deploy serving node

If you are simultaneously running streaming and batch queries, it will be difficult the guarantee the performance of both type of queries as CPU and memory resources are shared.

In this case, deploying a dedicated batch-serving cluster helps to alleviate resource competition and speed up queries. Additionally, compute node failures for streaming queries will not affect batch queries. 

This feature is only available if you deploy RisingWave in a distributed environment. These tutorials rely on the standalone version of RisingWave, which does not support deploying separate nodes. However, if you would like to learn more about this process, see the [official documentation](https://docs.risingwave.com/docs/current/dedicated-compute-node/).
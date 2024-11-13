
# :school: Awesome Stream Processing :school:

<div>
  <a
    href="https://risingwave.com/slack"
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
1. [**Basic stream processing workflow**](01-basic-streaming-workflow)

    Learn the fundamentals of ingesting, processing, transforming, and offloading data from streaming systems.
    1. [**Querying and processing event streaming data ✅**](/01-basic-streaming-workflow/01-query-process-streaming-data/)
      * Directly query data stored in event streaming systems (e.g., Kafka, Redpanda).
      * Continuously ingest and analyze data from event streaming systems.
    2. [**Bringing analytics closer to operational databases ✅**](/01-basic-streaming-workflow/02-bring-analytics-closer-to-odb/)
      * Offload event-driven queries (e.g., materialized views and triggers) from operational databases (e.g., MySQL, PostgreSQL).
    3. [**Real-time ETL (Extract, Transform, Load) ✅**](/01-basic-streaming-workflow/03-real-time-etl/)
      * Perform ETL continuously and incrementally.
2. [**Simple demonstrations ✅**](02-simple-demos/)
   * A collection of simple, self-contained demos showcasing how stream processing can be applied in specific industry use cases.
3. [**Solution demonstrations ✅**](03-solution-demos/)
   * A collection of comprehensive demos showcasing how to build a stream processing pipeline for real-world applications.


We use [RisingWave](https://github.com/risingwavelabs/risingwave) as the default stream processing system to run these demos. We also assume that you have [Kafka](https://kafka.apache.org/) and/or [PostgreSQL](https://www.postgresql.org/) installed and possess basic knowledge of how to use these systems. **These demos have been verified on Ubuntu and Mac.**

_**All you need is a laptop**_ 💻 - _**no cluster is required.**_

Any comments are welcome. Happy streaming!

Join our [Slack community](https://www.risingwave.com/slack) to engage in discussions with thousands of stream processing enthusiasts!

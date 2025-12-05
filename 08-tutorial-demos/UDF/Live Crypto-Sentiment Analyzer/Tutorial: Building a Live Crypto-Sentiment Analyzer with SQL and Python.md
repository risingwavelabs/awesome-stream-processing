# Tutorial: Building a Live Crypto-Sentiment Analyzer with SQL and Python

SQL is incredible for querying data, but it faces a major hurdle when you need to interact with the world outside your database.

If your data pipeline needs to **call an external API**, utilize **Python ecosystem libraries** (like NumPy or NLTK), or **invoke AI models**, standard SQL simply cannot handle it.

## The Problem: The "Microservices Sandwich"

In a traditional streaming architecture, this limitation forces you to introduce complex "glue" infrastructure. You often have to split the pipeline in the middle:

1. **Spin up a separate microservice** to pull data from Kafka.
2. **Process the data** with a Python script (and manually handle state or windowing logic).
3. **Push the results** to a separate database for analysis.

This "sandwich" approach adds significant latency and maintenance overhead. You are no longer just writing queries. You are managing distributed systems, handling offsets, and stitching together multiple components just to calculate a simple score.

## The Solution: RisingWave + Python UDFs

RisingWave is a streaming database compatible with PostgreSQL that eliminates this middle layer.

Instead of moving data out of the database for processing, RisingWave allows you to bring your Python logic into the SQL pipeline using **User-Defined Functions (UDFs)**.

In this tutorial, we will build a **Live Crypto-Sentiment Analyzer**. We will ingest a stream of news headlines and use a Python library (NLTK) to predict market movement.

### **How it works**

RisingWave bridges the gap using a **sidecar architecture**:

1. **RisingWave** handles the heavy lifting, such as stream ingestion, windowing, and state consistency.
2. **Your Python Script** handles the specific business logic, such as sentiment analysis using NLTK.
3. **High-Speed RPC** connects the two components. Data is batched and sent to your script via Apache Arrow to ensure the connection is fast and efficient.

> Why a Sidecar?
> 
> 
> We use an **external** Python process for this tutorial rather than embedding Python inside the kernel. This ensures isolation. If your heavy AI model hangs or crashes, it will not take down the entire database. You get the safety of a microservice with the simplicity of a SQL function.
> 

## A Step-by-Step Demo: **Live Crypto-Sentiment Analyzer**

We are going to create a pipeline that:

1. Ingests a mock stream of crypto news.
2. Sends the headline text to our external Python script.
3. Outputs a `BUY`, `SELL`, or `HOLD` signal in real-time.

The complete code is available here.

### The Architecture

We will use run three components in separated terminals:

1. **News Producer:** A script generating mock headlines into Kafka.
2. **UDF Server:** A Python container running the NLTK sentiment analysis.
3. **RisingWave:** The database that consumes the stream and calls the UDF.

### 1. The **News Producer (Kafka)**

We need a producer to feed streaming data into Kafka. Run `producer.py` locally. It generates random headlines chosen from fixed data.

```python
# producer.py
# --- CONFIGURATION ---
KAFKA_BROKER = "localhost:9092"
KAFKA_TOPIC = "news_stream"

# --- MAIN LOOP ---
try:
		# Initialize the Kafka connection
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BROKER,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )
    while True:
        data = get_random_news()
        producer.send(KAFKA_TOPIC, data)
        time.sleep(2.0)
```

You will observe the following information in the console.

```powershell
# output in console
🔌 Connecting to Kafka at localhost:9092...
✅ Connected. Sending random headlines to 'news_stream'...
(Press Ctrl+C to stop)
Sent: [1764739218] Solana network suffers outage due to heavy transaction volume
Sent: [1764739220] Dogecoin rallies after unexpected celebrity endorsement
Sent: [1764739222] Market stabilizes as traders await Federal Reserve meeting
```

### 2. The UDF Server (Python + NLTK)

Next, we write the logic. We'll use the `arrow-udf` library to interface with RisingWave and `nltk` to handle the sentiment scoring.

Notice that we decorate the function with `@udf`. This tells the server exactly how to map SQL types to Python types.

```python
# 1. Define the Batched UDF
@udf(input_types=["VARCHAR"], result_type="DOUBLE PRECISION", batch=True)
def get_sentiment(headlines: list[str]) -> list[float]:
    scores = []
    for headline in headlines:
        score = sid.polarity_scores(str(headline))['compound']
        scores.append(score)
    return scores

if __name__ == '__main__':
    # 2. Start the UDF Server
    server = UdfServer(location="localhost:8815")
    server.add_function(get_sentiment)
    server.serve()
```

When you run this, it will start listening for requests from the database:

```powershell
# output in console
added function: get_sentiment
Starting Sentiment UDF Server on port 8815...
listening on localhost:8815
```

### 3. **Wiring it up in RisingWave**

Now we connect to RisingWave and wire everything together.

**Step 1: Connect to the Data Stream**

We create a source that consumes the JSON data from our Kafka topic.

```sql
CREATE SOURCE news_feed (
    event_time TIMESTAMP,
    headline VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'news_stream',
    properties.bootstrap.server = 'localhost:9092',
    scan.startup.mode = 'latest'
) FORMAT PLAIN ENCODE JSON;
```

**Step 2: Register the Python Function**

We tell RisingWave that a function named `analyze_sentiment` exists at the address of our UDF container.

```sql
CREATE FUNCTION analyze_sentiment(varchar) 
RETURNS double precision 
AS get_sentiment 
USING LINK 'http://localhost:8815';
```

**Step 3: Create the Logic View**

Finally, we create a Materialized View. This view persists the results. As new headlines arrive in Kafka, RisingWave automatically batches them, sends them to the Python container, gets the score, and updates the view.

```sql
CREATE MATERIALIZED VIEW crypto_signals AS
SELECT 
		event_time,
    headline,
    analyze_sentiment(headline) as sentiment_score,
    CASE 
        WHEN analyze_sentiment(headline) > 0.05 THEN 'BUY'
        WHEN analyze_sentiment(headline) < -0.05 THEN 'SELL'
        ELSE 'HOLD'
    END as signal
FROM news_feed;
```

**Step 4: Query the results**

```sql
SELECT * FROM crypto_signals ORDER BY event_time DESC LIMIT 5

-- output
     event_time      |                             headline                             | sentiment_score | signal
---------------------+------------------------------------------------------------------+-----------------+--------
 2025-12-03 06:38:36 | Blockchain association releases annual transparency report       |               0 | HOLD
 2025-12-03 06:38:34 | Dogecoin rallies after unexpected celebrity endorsement          |          0.3182 | BUY
 2025-12-03 06:38:32 | Bitcoin hits new all-time high amid massive institutional buying |               0 | HOLD
 2025-12-03 06:38:30 | Major crypto exchange hacked, thousands of wallets drained       |         -0.6369 | SELL
 2025-12-03 06:38:28 | Ethereum surges 10% following successful network upgrade         |          0.5859 | BUY
```

## Summary

We just injected a Python NLP library into a SQL query.

By using RisingWave's UDF architecture, we achieved this without complex ETL pipelines or microservices glue code. The database handles the stream ingestion, windowing, and state management, while Python handles the specialized logic. Because the UDF runs in a sidecar pattern, your data infrastructure remains robust even if the Python script encounters issues.

## **Get Started with RisingWave**

- **Try RisingWave Today:**
    - [**Download the open-sourced version of RisingWave**](https://github.com/risingwavelabs/risingwave) to deploy on your own infrastructure.
    - Get started quickly with [**RisingWave Cloud**](https://cloud.risingwave.com/auth/signin/) for a fully managed experience.
- **Talk to Our Experts:** Have a complex use case or want to see a personalized demo? [**Contact us**](https://risingwave.com/contact-us/) to discuss how RisingWave can address your specific challenges.
- **Join Our Community:** Connect with fellow developers, ask questions, and share your experiences in our vibrant [**Slack community**](http://go.risingwave.com/slack).

If you’d like to see a personalized demo or discuss how this could work for your use case, please **contact our sales team**.
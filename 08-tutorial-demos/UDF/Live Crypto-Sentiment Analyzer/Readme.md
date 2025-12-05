# Live Crypto-Sentiment Analyzer Demo

This repository contains all source code for the "Live Crypto-Sentiment Analyzer" tutorial, which demonstrates building a real-time crypto news sentiment analysis pipeline using RisingWave, Kafka, and Python UDFs.

## Prerequisites
- Kafka (local or remote instance)
- RisingWave (local or cloud deployment)
- Python 3.8+
- Required Python packages: `kafka-python`, `nltk`, `arrow-udf`
- Download two python scripts in this repository.

## Prerequisites
### 1.  Start the News Producer
Generate mock crypto news headlines and send to Kafka:

```python
python producer.py
```
### 2.  Run the UDF Server
Start the Python UDF server for sentiment analysis:
```python
python sentiment.py
```
This will start a server on localhost:8815 to handle sentiment scoring requests.
### 3.  Configure RisingWave
Connect to your RisingWave instance and execute the SQL scripts in risingwave_ddl.sql to:
- Create a Kafka source
- Register the sentiment analysis UDF
- Create the materialized view for trading signals
### 4. Query Results
In RisingWave, query the crypto_signals view to see real-time sentiment scores and trading signals.

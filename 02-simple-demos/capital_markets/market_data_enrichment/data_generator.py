import json
from kafka import KafkaProducer
import random
from datetime import datetime, timedelta, timezone
import time

producer = KafkaProducer(
    bootstrap_servers='localhost:29092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',
    retries=3,
    max_in_flight_requests_per_connection=1
)
# Define assets and sectors
asset_ids = [1, 2, 3, 4, 5]
sectors = ["Technology", "Finance", "Healthcare", "Energy"]

try:
    while True:
        # Insert raw market data
        ts = datetime.now(timezone.utc).isoformat()
        timestamp = ts.replace('+00:00', 'Z')
        for asset_id in asset_ids:
            price = round(random.uniform(50, 150), 2)
            volume = random.randint(100, 5000)
            bid_price = round(price - random.uniform(0.1, 0.5), 2)
            ask_price = round(price + random.uniform(0.1, 0.5), 2)

            data = {
                "asset_id": asset_id,
                "timestamp": timestamp,
                "price": price, 
                "volume": volume,
                "bid_price": bid_price, 
                "ask_price": ask_price
            }
            producer.send('raw_market_data', data)

        # Insert enrichment data
        for asset_id in asset_ids:
            sector = random.choice(sectors)
            historical_volatility = round(random.uniform(0.1, 0.5), 2)
            sector_performance = round(random.uniform(-0.05, 0.05), 2)
            sentiment_score = round(random.uniform(-1, 1), 2)

            data = {
                "asset_id": asset_id,
                "sector": sector,
                "historical_volatility": historical_volatility,
                "sector_performance": sector_performance,
                "sentiment_score": sentiment_score,
                "timestamp": timestamp
            }
            producer.send('enrichment_data', data)
            print("Sent to enrichment_data:", data)

        producer.flush()
        time.sleep(2)

except KeyboardInterrupt:
    print("Data generation stopped.")
finally:
    producer.flush()
    print("Kafka producer closed.")
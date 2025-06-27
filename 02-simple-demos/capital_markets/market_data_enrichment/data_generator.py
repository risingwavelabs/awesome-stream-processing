import psycopg2
import random
from datetime import datetime, timedelta
import time

# RisingWave connection parameters
conn_params = {
    "dbname": "dev",
    "user": "root",
    "password": "",
    "host": "localhost",
    "port": "4566"
}

conn = psycopg2.connect(**conn_params)
cursor = conn.cursor()

# Define assets and sectors
asset_ids = [1, 2, 3, 4, 5]
sectors = ["Technology", "Finance", "Healthcare", "Energy"]

try:
    while True:
        # Insert raw market data
        for asset_id in asset_ids:
            timestamp = datetime.now()
            price = round(random.uniform(50, 150), 2)
            volume = random.randint(100, 5000)
            bid_price = round(price - random.uniform(0.1, 0.5), 2)
            ask_price = round(price + random.uniform(0.1, 0.5), 2)

            cursor.execute(
                """
                INSERT INTO raw_market_data (asset_id, timestamp, price, volume, bid_price, ask_price)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (asset_id, timestamp, price, volume, bid_price, ask_price)
            )

        # Insert enrichment data
        for asset_id in asset_ids:
            timestamp = datetime.utcnow()
            sector = random.choice(sectors)
            historical_volatility = round(random.uniform(0.1, 0.5), 2)
            sector_performance = round(random.uniform(-0.05, 0.05), 2)
            sentiment_score = round(random.uniform(-1, 1), 2)

            cursor.execute(
                """
                INSERT INTO enrichment_data (asset_id, sector, historical_volatility, sector_performance, sentiment_score, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (asset_id, sector, historical_volatility, sector_performance, sentiment_score, timestamp)
            )

        conn.commit()
        time.sleep(2)

except KeyboardInterrupt:
    print("Data generation stopped.")
finally:
    cursor.close()
    conn.close()
    print("Connection closed.")

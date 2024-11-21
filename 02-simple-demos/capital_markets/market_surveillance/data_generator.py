import psycopg2
import random
from datetime import datetime
import time

# RisingWave connection
conn_params = {
    "dbname": "dev",
    "user": "root",
    "password": "",
    "host": "localhost",
    "port": "4566"
}

conn = psycopg2.connect(**conn_params)
cursor = conn.cursor()

# Define assets and random traders
asset_ids = [1, 2, 3, 4, 5]
traders = list(range(100, 200))

try:
    while True:
        # Insert trade data
        for asset_id in asset_ids:
            trade_id = random.randint(10000, 99999)
            timestamp = datetime.now()
            price = round(random.uniform(50, 150), 2)
            volume = random.randint(10, 1000)
            buyer_id = random.choice(traders)
            seller_id = random.choice([t for t in traders if t != buyer_id])

            cursor.execute(
                """
                INSERT INTO trade_data (trade_id, asset_id, timestamp, price, volume, buyer_id, seller_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (trade_id, asset_id, timestamp, price, volume, buyer_id, seller_id)
            )

        # Insert market data
        for asset_id in asset_ids:
            timestamp = datetime.now()
            bid_price = round(random.uniform(50, 149), 2)
            ask_price = round(bid_price + random.uniform(0.5, 2.5), 2)
            price = round((bid_price + ask_price) / 2, 2)
            rolling_volume = random.randint(1000, 10000)

            cursor.execute(
                """
                INSERT INTO market_data (asset_id, timestamp, bid_price, ask_price, price, rolling_volume)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (asset_id, timestamp, bid_price, ask_price, price, rolling_volume)
            )

        conn.commit()
        time.sleep(1)

except KeyboardInterrupt:
    print("Data generation stopped.")
finally:
    cursor.close()
    conn.close()
    print("Connection closed.")

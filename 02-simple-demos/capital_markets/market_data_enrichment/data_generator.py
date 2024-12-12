import psycopg2
import random
from datetime import datetime, timedelta
import time
from decimal import Decimal, ROUND_HALF_UP

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
        print("\n=== Generating Market Data ===")
        for asset_id in asset_ids:
            timestamp = datetime.now()
            # Convert to Decimal and round to 2 decimal places
            price = Decimal(str(random.uniform(50, 150))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            volume = random.randint(100, 5000)
            bid_price = (price - Decimal(str(random.uniform(0.1, 0.5)))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            ask_price = (price + Decimal(str(random.uniform(0.1, 0.5)))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

            cursor.execute(
                """
                INSERT INTO raw_market_data (asset_id, timestamp, price, volume, bid_price, ask_price)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (asset_id, timestamp, price, volume, bid_price, ask_price)
            )
            print(f"📈 Asset {asset_id}: Price=${price} | Vol={volume} | Bid=${bid_price} | Ask=${ask_price}")

        # Insert enrichment data
        print("\n=== Generating Enrichment Data ===")
        for asset_id in asset_ids:
            timestamp = datetime.now()
            sector = random.choice(sectors)
            historical_volatility = Decimal(str(random.uniform(0.1, 0.5))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            sector_performance = Decimal(str(random.uniform(-0.05, 0.05))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            sentiment_score = Decimal(str(random.uniform(-1, 1))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

            cursor.execute(
                """
                INSERT INTO enrichment_data (asset_id, sector, historical_volatility, sector_performance, sentiment_score, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (asset_id, sector, historical_volatility, sector_performance, sentiment_score, timestamp)
            )
            print(f"📊 Asset {asset_id}: Sector={sector} | Volatility={historical_volatility} | Sentiment={sentiment_score}")

        conn.commit()
        print("\n✅ Data committed successfully")
        print("Waiting 0.3 seconds for next batch...\n")
        time.sleep(0.3)

except KeyboardInterrupt:
    print("Data generation stopped.")
finally:
    cursor.close()
    conn.close()
    print("Connection closed.")

import time
import json
import random
from kafka import KafkaProducer

# --- CONFIGURATION ---
# Use "localhost:9092" if running this script on your host machine.
# Use "kafka:9092" if running this script inside a Docker container.
KAFKA_BROKER = "localhost:9092"
KAFKA_TOPIC = "news_stream"

# --- THE DATA ---
# A fixed list of headlines to rotate through
HEADLINES = [
    "Bitcoin hits new all-time high amid massive institutional buying",  # Strong Positive
    "Major crypto exchange hacked, thousands of wallets drained",        # Strong Negative
    "Market stabilizes as traders await Federal Reserve meeting",        # Neutral
    "Ethereum surges 10% following successful network upgrade",          # Positive
    "Regulatory crackdown causes panic selling across altcoins",         # Negative
    "Dogecoin rallies after unexpected celebrity endorsement",           # Positive
    "Blockchain association releases annual transparency report",        # Neutral
    "Solana network suffers outage due to heavy transaction volume",     # Negative
    "Analysts predict bullish trend for the upcoming quarter",           # Positive
    "Investors fearful as inflation data comes in higher than expected"   # Negative
]

def get_random_news():
    return {
        "event_time": int(time.time()),
        "headline": random.choice(HEADLINES)
    }

# --- MAIN LOOP ---
if __name__ == "__main__":
    print(f"🔌 Connecting to Kafka at {KAFKA_BROKER}...")
    
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKER,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        print(f"✅ Connected. Sending random headlines to '{KAFKA_TOPIC}'...")
        print("(Press Ctrl+C to stop)")

        while True:
            data = get_random_news()
            producer.send(KAFKA_TOPIC, data)
            print(f"Sent: [{data['event_time']}] {data['headline']}")
            time.sleep(2.0)

    except KeyboardInterrupt:
        print("\n🛑 Stopping producer...")
        if 'producer' in locals():
            producer.close()
    except Exception as e:
        print(f"\n❌ Error: {e}")
        print(f"Ensure Kafka is running at {KAFKA_BROKER}")
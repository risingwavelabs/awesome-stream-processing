import json
import time
import random
import argparse
from datetime import datetime, timedelta
from kafka import KafkaProducer

# ---- Simple knobs 
NUM_PLAYERS = 50
NUM_MATCHES = 6
KEY_BY = "player_name"   # or "match_id"

# -------- Data generation 
def generate_fortnite_data(num_players=10, num_matches=6):
    players = []
    now = datetime.now()
    for _ in range(num_players):
        player_name = generate_player_name()
        for match_index in range(num_matches):
            ts = (now + timedelta(minutes=match_index * 10 + random.randint(-3, 3))).strftime("%Y-%m-%d %H:%M:%S")
            players.append({
                "ts": ts,
                "match_id": match_index + 1,
                "player_name": player_name,
                "mental_state": random.choice(["sober", "focused", "distracted", "tired"]),
                "eliminations": random.randint(0, 5),
                "assists": random.randint(0, 3),
                "headshot_kills": random.randint(0, 10),
                "damage_dealt": random.randint(500, 2000),
                "damage_taken": random.randint(50, 600),
                "healing_done": random.randint(0, 1000),
                "accuracy": round(random.uniform(10, 60), 2),
                "time_survived": generate_time_survived_in_seconds(),
                "player_rank": random.randint(1, 50),
            })
    return players

def generate_player_name():
    first = ["John","Jane","PlayerX","Max","Samantha","Alex","Chris","Taylor","Jordan","Robin","Alexis","Blake","Morgan","Riley","Cameron","Sydney","Jamie","Casey","Pat","Skyler","Charlie","Dakota"]
    last  = ["Doe","Smith","Wilson","Williams","Brown","Jones","Davis","Miller","Anderson","Thomas","Taylor","Martinez","Lee","Perez","Young","Walker","Hall","Allen","Hernandez","King","Wright"]
    return f"{random.choice(first)} {random.choice(last)}"

def generate_time_survived_in_seconds():
    return random.randint(5, 30) * 60 + random.randint(0, 59)

# -------- Kafka producer --------
def produce_to_kafka(bootstrap_servers: str, topic: str, rate: float, loop: bool):
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers.split(","),
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        key_serializer=lambda k: (str(k).encode("utf-8") if k is not None else None),
        acks="all", linger_ms=5, retries=3, request_timeout_ms=30000,
    )
    try:
        while True:
            for rec in generate_fortnite_data(NUM_PLAYERS, NUM_MATCHES):
                key = rec.get(KEY_BY)
                producer.send(topic, value=rec, key=key)
                if rate > 0:
                    time.sleep(1.0 / rate)
            producer.flush()
            if not loop:
                break
    finally:
        producer.flush()
        producer.close()
        print("Producer closed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fortnite stats producer (tiny CLI)")
    parser.add_argument("bootstrap", nargs="?", default="kafka:9092", help="Kafka bootstrap servers")
    parser.add_argument("topic", nargs="?", default="player_stats", help="Kafka topic")
    parser.add_argument("--loop", action="store_true", help="Continuously send data")
    parser.add_argument("--rate", type=float, default=5.0, help="Msgs/sec (0 = max)")
    args = parser.parse_args()

    produce_to_kafka(args.bootstrap, args.topic, args.rate, args.loop)

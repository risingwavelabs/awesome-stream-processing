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

# Establish a connection to RisingWave
conn = psycopg2.connect(**conn_params)
cursor = conn.cursor()

# Define parameters
num_users = 10
num_positions = 5
leagues = ["MLB", "NBA", "NFL", "NHL", "Soccer", "Tennis"]
risk_levels = ["High", "Medium", "Low"]

# Insert user profiles into RisingWave
for user_id in range(1, num_users + 1):
    username = f"user_{user_id}"
    preferred_league = random.choice(leagues)
    avg_bet_size = round(random.uniform(50, 500), 2)
    risk_tolerance = random.choice(risk_levels)

    cursor.execute(
        """
        INSERT INTO user_profiles (user_id, username, preferred_league, avg_bet_size, risk_tolerance)
        VALUES (%s, %s, %s, %s, %s)
        """,
        (user_id, username, preferred_league, avg_bet_size, risk_tolerance)
    )

conn.commit()
print("Inserted user profiles.")

# Insert synthetic betting history and real-time position data continuously
try:
    while True:
        # Generate historical bets for each user
        for user_id in range(1, num_users + 1):
            position_id = random.randint(1, num_positions)
            bet_amount = round(random.uniform(20, 300), 2)
            result = random.choice(["Win", "Loss"])
            profit_loss = bet_amount * (random.uniform(0.5, 2) if result == "Win" else -1 * random.uniform(0.5, 1))
            timestamp = datetime.now() - timedelta(days=random.randint(1, 10))

            cursor.execute(
                """
                INSERT INTO betting_history (user_id, position_id, bet_amount, result, profit_loss, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (user_id, position_id, bet_amount, result, profit_loss, timestamp)
            )

        # Generate real-time betting positions for each user
        for user_id in range(1, num_users + 1):
            position_id = random.randint(1, num_positions)
            position_name = f"Position_{position_id}"
            league = random.choice(leagues)
            stake_amount = round(random.uniform(50, 500), 2)
            expected_return = round(stake_amount * random.uniform(1.1, 2.5), 2)
            current_odds = round(random.uniform(1.0, 5.0), 2)
            profit_loss = round((current_odds - 1.5) * stake_amount, 2)
            timestamp = datetime.now()

            cursor.execute(
                """
                INSERT INTO positions (position_id, position_name, user_id, league, stake_amount, expected_return,
                current_odds, profit_loss, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (position_id, position_name, user_id, league, stake_amount, expected_return, current_odds, profit_loss, timestamp)
            )

        conn.commit()
        print("Inserted betting history and real-time positions.")

        time.sleep(2)

except KeyboardInterrupt:
    print("Data insertion stopped.")

finally:
    cursor.close()
    conn.close()
    print("Connection closed.")

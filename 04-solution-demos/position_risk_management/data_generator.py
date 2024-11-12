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
num_positions = 10
leagues = ["MLB", "NBA", "NFL", "NHL", "Soccer", "Tennis"]
teams = ["Team A", "Team B", "Team C", "Team D", "Team E"]
bookmakers = ["DraftKings", "FanDuel", "BetMGM", "Caesars"]

# Insert betting positions into RisingWave
try:
    while True:
        for i in range(num_positions):
            position_id = i + 1
            league = random.choice(leagues)
            team1 = random.choice(teams)
            team2 = random.choice([team for team in teams if team != team1])
            position_name = f"{team1} vs {team2}"
            stake_amount = round(random.uniform(50, 500), 2)
            expected_return = round(stake_amount * random.uniform(1.1, 2.5), 2)
            max_risk = round(stake_amount * random.uniform(1.0, 1.5), 2)
            fair_value = round(random.uniform(1.0, 5.0), 2)
            current_odds = round(fair_value + random.uniform(-0.5, 0.5), 2)
            profit_loss = round((current_odds - fair_value) * stake_amount, 2)
            exposure = round(stake_amount * random.uniform(0.8, 1.2), 2)
            timestamp = datetime.now()

            cursor.execute(
                """
                INSERT INTO positions (position_id, league, position_name, timestamp, stake_amount, expected_return, 
                max_risk, fair_value, current_odds, profit_loss, exposure) 
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (position_id, league, position_name, timestamp, stake_amount, expected_return, max_risk,
                 fair_value, current_odds, profit_loss, exposure)
            )
        
        conn.commit()
        print("Inserted betting positions data.")

        for i in range(num_positions):
            position_id = i + 1
            bookmaker = random.choice(bookmakers)
            market_price = round(random.uniform(1.0, 5.0), 2)
            volume = random.randint(100, 1000)
            timestamp = datetime.now()

            cursor.execute(
                """
                INSERT INTO market_data (position_id, bookmaker, market_price, volume, timestamp) 
                VALUES (%s, %s, %s, %s, %s)
                """,
                (position_id, bookmaker, market_price, volume, timestamp)
            )

        conn.commit()
        print("Inserted market data.")

        time.sleep(2)

except KeyboardInterrupt:
    print("Data insertion stopped.")

finally:
    cursor.close()
    conn.close()
    print("Connection closed.")
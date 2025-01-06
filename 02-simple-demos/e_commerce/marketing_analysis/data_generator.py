import psycopg2
import random
from datetime import datetime, timedelta
import time
import uuid

# Database connection parameters
conn_params = {
    "dbname": "dev",
    "user": "root",
    "password": "",
    "host": "localhost",
    "port": "4566"
}

# Sample data
CHANNELS = ['email', 'social', 'search', 'display']
EVENT_TYPES = ['impression', 'click', 'conversion']
UTM_SOURCES = ['google', 'facebook', 'instagram', 'email', 'linkedin']
UTM_MEDIUMS = ['cpc', 'organic', 'social', 'email', 'display']
CAMPAIGN_TYPES = ['regular', 'ab_test']
VARIANT_TYPES = ['subject_line', 'creative', 'landing_page']

def create_campaigns(conn, num_campaigns=10):
    cur = conn.cursor()
    campaigns = []
    
    for i in range(num_campaigns):
        campaign_id = f"camp_{uuid.uuid4().hex[:8]}"
        is_ab_test = random.choice(CAMPAIGN_TYPES) == 'ab_test'
        
        cur.execute("""
            INSERT INTO campaigns 
            (campaign_id, campaign_name, campaign_type, start_date, end_date, budget, target_audience)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (
            campaign_id,
            f"Campaign {i+1}",
            'ab_test' if is_ab_test else 'regular',
            datetime.now() - timedelta(days=random.randint(1, 30)),
            datetime.now() + timedelta(days=random.randint(1, 30)),
            random.uniform(1000, 10000),
            random.choice(['new_customers', 'existing_customers', 'all'])
        ))
        
        if is_ab_test:
            # Create variants for A/B test campaigns
            for variant in ['A', 'B', 'Control']:
                cur.execute("""
                    INSERT INTO ab_test_variants
                    (variant_id, campaign_id, variant_name, variant_type, content_details)
                    VALUES (%s, %s, %s, %s, %s)
                """, (
                    str(uuid.uuid4()),
                    campaign_id,
                    variant,
                    random.choice(VARIANT_TYPES),
                    f"Content for variant {variant}"
                ))
        
        campaigns.append(campaign_id)
    
    conn.commit()
    return campaigns

def generate_marketing_event(campaign_ids):
    campaign_id = random.choice(campaign_ids)
    event_type = random.choice(EVENT_TYPES)
    
    return {
        'event_id': str(uuid.uuid4()),
        'user_id': random.randint(1, 1000),
        'campaign_id': campaign_id,
        'channel_type': random.choice(CHANNELS),
        'event_type': event_type,
        'amount': round(random.uniform(50, 500), 2) if event_type == 'conversion' else 0,
        'utm_source': random.choice(UTM_SOURCES),
        'utm_medium': random.choice(UTM_MEDIUMS)
    }

def simulate_marketing_events(conn, duration_minutes=60, events_per_minute=50):
    cur = conn.cursor()
    
    # Create campaigns first
    campaign_ids = create_campaigns(conn)
    
    start_time = datetime.now()
    end_time = start_time + timedelta(minutes=duration_minutes)
    
    print(f"Starting marketing event simulation for {duration_minutes} minutes...")
    
    while datetime.now() < end_time:
        for _ in range(events_per_minute):
            event = generate_marketing_event(campaign_ids)
            cur.execute("""
                INSERT INTO marketing_events 
                (event_id, user_id, campaign_id, channel_type, event_type, 
                amount, utm_source, utm_medium, utm_campaign)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                event['event_id'], event['user_id'], event['campaign_id'],
                event['channel_type'], event['event_type'], event['amount'],
                event['utm_source'], event['utm_medium'], event['campaign_id']
            ))
        
        conn.commit()
        print(f"Generated {events_per_minute} events. Timestamp: {datetime.now()}")
        time.sleep(1)

conn = psycopg2.connect(**conn_params)
print("Connected to RisingWave successfully!")


try:
    while True:
        simulate_marketing_events(conn)
except KeyboardInterrupt:
    print("Data generation stopped.")
finally:
    cursor.close()
    conn.close()
    print("Connection closed.")
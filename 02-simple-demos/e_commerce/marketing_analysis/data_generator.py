import json
import random
from datetime import datetime, timedelta
import time
import uuid
from kafka import KafkaProducer

# Database connection parameters
producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',
    retries=3,
    max_in_flight_requests_per_connection=1
)

# Sample data
CHANNELS = ['email', 'social', 'search', 'display']
EVENT_TYPES = ['impression', 'click', 'conversion']
UTM_SOURCES = ['google', 'facebook', 'instagram', 'email', 'linkedin']
UTM_MEDIUMS = ['cpc', 'organic', 'social', 'email', 'display']
CAMPAIGN_TYPES = ['regular', 'ab_test']
VARIANT_TYPES = ['subject_line', 'creative', 'landing_page']

def now_ts():
    return datetime.now(timezone.utc).isoformat().replace('+00:00','Z')

def seed_campaigns(num_campaigns=10):
    """Emit campaigns (and any AB variants) into Kafka once at startup."""
    campaign_ids = []
    for i in range(num_campaigns):
        cid = f"camp_{uuid.uuid4().hex[:8]}"
        ctype = random.choice(CAMPAIGN_TYPES)
        campaign = {
            "campaign_id":    cid,
            "campaign_name":  f"Campaign {i+1}",
            "campaign_type":  ctype,
            "start_date":     now_ts(),
            "end_date":       (datetime.now(timezone.utc) + timedelta(days=random.randint(1,30))).isoformat(),
            "budget":         round(random.uniform(1000,10000),2),
            "target_audience": random.choice(['new_customers','existing_customers','all'])
        }
        producer.send('campaigns', campaign)
        if ctype == 'ab_test':
            for variant in ['A','B','Control']:
                var = {
                    "variant_id":      str(uuid.uuid4()),
                    "campaign_id":     cid,
                    "variant_name":    variant,
                    "variant_type":    random.choice(VARIANT_TYPES),
                    "content_details": f"Content for variant {variant}"
                }
                producer.send('ab_test_variants', var)
        campaign_ids.append(cid)
    producer.flush()
    return campaign_ids

def generate_event(campaign_ids):
    """Emit a single marketing event to Kafka."""
    cid = random.choice(campaign_ids)
    et  = random.choice(EVENT_TYPES)
    ev = {
        "event_id":      str(uuid.uuid4()),
        "user_id":       random.randint(1,1000),
        "campaign_id":   cid,
        "channel_type":  random.choice(CHANNELS),
        "event_type":    et,
        "amount":        round(random.uniform(50,500),2) if et=='conversion' else 0,
        "utm_source":    random.choice(UTM_SOURCES),
        "utm_medium":    random.choice(UTM_MEDIUMS),
        "utm_campaign":  cid,
        "timestamp":     now_ts()
    }
    producer.send('marketing_events', ev)
    
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
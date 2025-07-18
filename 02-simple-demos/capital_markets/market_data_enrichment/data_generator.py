import json
import random
import uuid
import time
from datetime import datetime, timezone
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',
    retries=3,
    max_in_flight_requests_per_connection=1
)

CHANNELS      = ['email', 'social', 'search', 'display']
EVENT_TYPES   = ['impression', 'click', 'conversion']
UTM_SOURCES   = ['google', 'facebook', 'instagram', 'email', 'linkedin']
UTM_MEDIUMS   = ['cpc', 'organic', 'social', 'email', 'display']
CAMPAIGN_TYPES= ['regular', 'ab_test']
VARIANT_TYPES= ['subject_line', 'creative', 'landing_page']

def now_iso():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

def seed_campaigns(n=10):
    ids = []
    for i in range(n):
        cid = f"camp_{uuid.uuid4().hex[:8]}"
        ctype = random.choice(CAMPAIGN_TYPES)
        # send campaign definition
        producer.send('campaigns', {
            'campaign_id':   cid,
            'campaign_name': f"Campaign {i+1}",
            'campaign_type': ctype,
            'start_date':    now_iso(),
            'end_date':      (datetime.now(timezone.utc) + random.randint(1,30)*timezone.utc).isoformat(),
            'budget':        round(random.uniform(1000,10000), 2),
            'target_audience': random.choice(['new_customers','existing_customers','all'])
        })
        # if AB test, send variants
        if ctype == 'ab_test':
            for var in ['A','B','Control']:
                producer.send('ab_test_variants', {
                    'variant_id':      str(uuid.uuid4()),
                    'campaign_id':     cid,
                    'variant_name':    var,
                    'variant_type':    random.choice(VARIANT_TYPES),
                    'content_details': f"Content for {var}"
                })
        ids.append(cid)
    producer.flush()
    return ids

# 4) Emit marketing events
def emit_events(campaign_ids, per_batch=50):
    for _ in range(per_batch):
        cid = random.choice(campaign_ids)
        et  = random.choice(EVENT_TYPES)
        producer.send('marketing_events', {
            'event_id':     str(uuid.uuid4()),
            'user_id':      random.randint(1,1000),
            'campaign_id':  cid,
            'channel_type': random.choice(CHANNELS),
            'event_type':   et,
            'amount':       round(random.uniform(50,500),2) if et=='conversion' else 0,
            'utm_source':   random.choice(UTM_SOURCES),
            'utm_medium':   random.choice(UTM_MEDIUMS),
            'utm_campaign': cid,
            'timestamp':    now_iso()
        })

# 5) Main loop
if __name__ == "__main__":
    campaign_ids = seed_campaigns(10)
    print("Seeded campaigns & variants into Kafka.")
    try:
        while True:
            emit_events(campaign_ids, per_batch=50)
            producer.flush()
            print(f"Sent batch at {now_iso()}")
            time.sleep(1)   # one batch per second
    except KeyboardInterrupt:
        print("Generator stopped by user.")
    finally:
        producer.flush()
        producer.close()

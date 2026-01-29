import os, time, json, random
import requests
import datagen

EVENTS_API_URL = os.getenv("EVENTS_API_URL", "http://localhost:8000")
BASE_INTERVAL_SEC = float(os.getenv("SEND_INTERVAL_SEC", "0.3"))   # base sleep
EVENT_BATCH_SIZE = int(os.getenv("EVENT_BATCH_SIZE", "300"))       # NDJSON batch lines
DIM_REFRESH_PROB = float(os.getenv("DIM_REFRESH_PROB", "0.03"))    # occasionally resend user/device (simulating updates)
BURST_PROB = float(os.getenv("BURST_PROB", "0.12"))                # traffic spike chance
BURST_MULT = int(os.getenv("BURST_MULT", "5"))                     # how many sessions in a burst

def post_sql(sql: str):
    url = f"{EVENTS_API_URL}/v1/sql"
    r = requests.post(url, data=sql, timeout=30)
    r.raise_for_status()
    return r.text

def post_json(table: str, payload: dict):
    url = f"{EVENTS_API_URL}/v1/events?name={table}"
    r = requests.post(url, data=json.dumps(payload), headers={"Content-Type": "application/json"}, timeout=15)
    r.raise_for_status()

def post_ndjson(table: str, rows: list[dict]):
    """
    NDJSON: one JSON object per line.
    Events API supports NDJSON ingestion to push many events per request.
    """
    url = f"{EVENTS_API_URL}/v1/events?name={table}"
    body = "\n".join(json.dumps(x) for x in rows) + "\n"
    r = requests.post(url, data=body.encode("utf-8"), headers={"Content-Type": "application/x-ndjson"}, timeout=30)
    r.raise_for_status()

def wait_for_api():
    while True:
        try:
            post_sql("SELECT 1;")
            return
        except Exception as e:
            print(f"[wait] Events API not ready: {e}")
            time.sleep(2)

BOOTSTRAP_SQL = """
-- Paste the SQL from sections:
-- 1) tables
-- 1B) latest views
-- 2) clickstream_joined_mv
-- 3) session_kpi_mv
"""

if __name__ == "__main__":
    wait_for_api()

    try:
        print("[bootstrap] creating schema")
        post_sql(BOOTSTRAP_SQL)
    except Exception as e:
        print(f"[bootstrap] continuing (maybe already exists): {e}")

    # Seed page catalog once (realistic: page metadata exists before traffic)
    try:
        for rec in datagen.gen_page_catalog_records():
            post_json("page_catalog", rec)
        print("[seed] page_catalog seeded")
    except Exception as e:
        print(f"[seed] page_catalog seed skipped: {e}")

    # caches to make traffic recurring (more realistic than random-new user every time)
    user_pool = [random.randint(100000, 200000) for _ in range(2000)]
    device_pool = {}  # user_id -> device_id + device record

    # event buffer for NDJSON batching
    event_buffer = []

    print("[run] realistic clickstream -> NDJSON batches")

    while True:
        # burst mode (spikes)
        sessions_to_generate = 1
        if random.random() < BURST_PROB:
            sessions_to_generate = BURST_MULT

        for _ in range(sessions_to_generate):
            user_id = random.choice(user_pool)

            # user profile (sometimes updated / resent)
            if random.random() < DIM_REFRESH_PROB:
                post_json("users", datagen.gen_user(user_id))

            # device per user (sticky-ish)
            if user_id not in device_pool or random.random() < 0.05:
                device_id, device = datagen.gen_device()
                device_pool[user_id] = (device_id, device)
                post_json("devices", device)
            else:
                device_id, device = device_pool[user_id]
                if random.random() < DIM_REFRESH_PROB:
                    # simulate browser upgrade, etc.
                    post_json("devices", datagen.gen_device()[1])

            # campaign per session (not always present, direct traffic sometimes)
            if random.random() < 0.72:
                campaign_id, campaign = datagen.gen_campaign()
                post_json("campaigns", campaign)
            else:
                campaign_id = None

            session_id = f"SESS-{random.randint(1000000, 9999999)}"
            post_json("sessions", datagen.gen_session(session_id, user_id, device_id))

            # build a journey (multiple events)
            cid = campaign_id if campaign_id else "CMP-000000"  # keep join stable even if missing
            if not campaign_id:
                # ensure a default campaign exists at least once
                post_json("campaigns", {
                    "campaign_id": "CMP-000000",
                    "source": "direct",
                    "medium": "none",
                    "campaign": "none",
                    "content": "",
                    "term": "",
                    "ingested_at": datagen.iso(datagen.now_utc()),
                })

            journey_events = datagen.gen_session_journey(user_id, session_id, cid)

            # introduce arrival out-of-order (network jitter): shuffle small percentage
            if random.random() < 0.10:
                random.shuffle(journey_events)

            event_buffer.extend(journey_events)

        # flush NDJSON batch when buffer large enough
        if len(event_buffer) >= EVENT_BATCH_SIZE:
            # take a chunk to keep requests bounded
            chunk = event_buffer[:EVENT_BATCH_SIZE]
            event_buffer = event_buffer[EVENT_BATCH_SIZE:]
            try:
                post_ndjson("clickstream_events", chunk)
                print(f"[ndjson] sent {len(chunk)} events")
            except Exception as e:
                print(f"[ndjson] failed, retry later: {e}")
                # push back and slow down a bit
                event_buffer = chunk + event_buffer
                time.sleep(2.0)

        time.sleep(BASE_INTERVAL_SEC)

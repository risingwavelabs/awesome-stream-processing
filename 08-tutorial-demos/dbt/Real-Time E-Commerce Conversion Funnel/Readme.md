

# Real-Time E-Commerce Conversion Funnel

This demo shows how to build a real-time streaming pipeline using **RisingWave** and **dbt**.

Instead of static batch updates, we will build a conversion funnel (Page View → Add to Cart → Purchase) that updates continuously as data flows in.

## 📂 File Structure

```text
.
├── gen_data.py              # Python script to generate mock JSON traffic to Kafka
├── dbt_project.yml          # dbt project configuration
├── profiles.yml             # Connection profile for RisingWave
├── requirements.txt         # Python dependencies
└── models/
    ├── src_page_views.sql   # Kafka Source definition
    ├── src_cart_events.sql  # Kafka Source definition
    ├── src_purchases.sql    # Kafka Source definition
    └── funnel.sql           # The core logic: Streaming joins & aggregation
```

## 🛠 Prerequisites

*   **RisingWave:** [Download the binary](https://github.com/risingwavelabs/risingwave/releases) and unzip it.
*   **Kafka:** Ensure you have a local Kafka broker running on port `9092`.
*   **Python 3.8+**

## 🚀 Quick Start

### 1. Install Dependencies
Create a virtual environment and install the required tools:
```bash
python3 -m venv venv
source venv/bin/activate
python3 -m pip install dbt-risingwave
```

### 2. Start the Infrastructure
Make sure your local Kafka is running. Then, start RisingWave in standalone mode:

```bash
# In a new terminal
risingwave
```

### 3. Start Data Generation
Run the Python script to start sending mock events (`page_views`, `cart_events`, `purchases`) to Kafka:

```bash
# In a new terminal
source venv/bin/activate
python gen_data.py
```

### 4. Deploy the Pipeline (dbt)
Apply the SQL models to RisingWave. This creates the sources and the persistent background streaming jobs.

```bash
# We use --profiles-dir . to use the local profiles.yml
dbt run --profiles-dir .
```

### 5. View Real-Time Results
Connect to RisingWave via Postgres to watch the funnel metrics update live:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Run this query repeatedly (or use `watch`) to see the numbers tick up:
```sql
SELECT * FROM funnel ORDER BY window_start DESC LIMIT 5;
```
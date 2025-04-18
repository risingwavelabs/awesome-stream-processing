1. Clone [this repository](https://github.com/risingwavelabs/awesome-stream-processing), and navigate to the current folder.

```bash
cd 03-solution-demos/spoofing_detection_with_live_market_data
```

2. Install and start RisingWave in the `single_node` mode. You can do this by using Homebrew or Docker. 

Docker:


2. Create the virtual environment (using uv, or use python3.9 -m venv .venv)

```bash
uv venv -p 3.9
source .venv/bin/activate  # Activate the environment (Linux/macOS)
# OR: .venv\Scripts\activate (Windows)

3. Install dependencies
```bash
pip install databento risingwave-py pandas
```


6.  Set the `DATABENTO_API_KEY` environment variable:
```bash
export DATABENTO_API_KEY="your_actual_databento_api_key" # db-hmhbKcueMThDJfMuVJsCD7pNPvyMe
```

7.  Run the scripts in order

```bash
python setup_tables.py
python ingest_data.py
psql -h localhost -p 4566 -d dev -U root -f spoofing_alerts.sql
python subscribe_alerts.py
```

1. Clone [this repository](https://github.com/risingwavelabs/awesome-stream-processing), and navigate to the current folder.

```bash
cd 03-solution-demos/spoofing_detection_with_live_market_data
```

2. Install and start RisingWave in the `single_node` mode. You can do this by using Homebrew or Docker. See [RisingWave quickstart](https://docs.risingwave.com/get-started/quickstart) for details.

  ```bash
  # Docker
  docker run -it --pull=always -p 4566:4566 -p 5691:5691 risingwavelabs/risingwave:latest single_node
  ```

2. Create the virtual environment.

  ```bash
  python -m venv .venv
  source .venv/bin/activate  # Activate the environment (Linux/macOS)
  # OR: .venv\Scripts\activate.bat (Windows Command Prompt)
  # OR: .venv\Scripts\activate.ps1 (Windows PowerShell)
  ```
3. Install dependencies
  ```bash
  pip install databento risingwave-py pandas
  ```

4.  Set the `DATABENTO_API_KEY` environment variable:
  ```bash
  export DATABENTO_API_KEY="your_actual_databento_api_key" # You need to sign up at Databento first and then grab your API key.
  ```

5. Log into `psql` and create tables and materialized views. You can also grab the `CREATE TABLE` and `CREATE MATERIALIZED VIEW` statements from `tables.sql` and `spoofing_alerts.sql` and run them one by one.

  - Log into RisingWave:
  ```bash
  psql -h localhost -p 4566 -d dev -U root
  ```
  - In `psql`, run the queries in the files.
  ```bash label="Create the tables and materialized view"
  dev=> \i tables.sql
  dev=> \i spoofing_alerts.sql
  ```

6.  Now ingest market data from Databento, and set up the alert subscription logic. You might want to run them in separate terminal windows, so that you can view the progress separately.

    Note that you don't need to do anything on the RisingWave side, as the detection logic is running in the form of a materalized view in                 RisingWave(continuous streaming job).

  ```bash
  python ingest_data.py
  python subscribe_alerts.py
  ```

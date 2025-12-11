## Background

In clinical settings—whether hospitals, home health services, or remote patient monitoring—every second counts. Medical devices continuously stream vital sign data (heart rate, blood oxygen, blood glucose) at high frequency, generating a constant flow of critical information. But this data deluge presents a pressing challenge: how do you process, analyze, and act on real-time vital signs to detect abnormalities and trigger alerts—without latency, complexity, or resource bloat?

Traditional healthcare data systems often rely on batch processing or rigid databases, leading to delayed alerts that compromise patient safety. Custom stream processing solutions require complex coding and infrastructure management, putting them out of reach for many healthcare tech teams.

Thus, we built a demo that combines the high-throughput data ingestion of Kafka with the stream processing power of RisingWave—delivering a simple, efficient, and clinically relevant real-time dashboard. This solution transforms raw vital sign streams into instant alerts, trend analysis, and actionable insights, all with minimal code and infrastructure overhead.



## QuickStart

### Prerequisites

Ensure that [RisingWave](https://docs.risingwave.com/get-started/quickstart), [MySQL](https://www.mysql.com/cn/) and [Kafka](https://kafka.apache.org/) have been successfully installed!

### Quick Start

1. **Clone the Repository.**

   ```
   git clone <https://github.com/risingwavelabs/awesome-stream-processing.git>
   ```

2. **Go to the demo directory.**

   ```
   cd health_care
   ```

3. **Run the initial shell script to create Kafka topics and tables in RisingWave and MySQL.**

   ```
   sh initial.sh
   ```

4. **Run the python script to generate data.**

   ```
   python generate_data.py
   ```

5. **Run the Backedend Server.**

   ```
   python alert_server.py
   ```

6. **Launch the dashboard.**

   Open `dashboard.html` in your browser.




## Visualization

### Interface preview

<img src="./images/Interface Preview.png" alt="Interface Preview" style="zoom:33%;" />

### Live Alert Monitoring & Triage

<img src="./images/Alerts List.png" alt="Alerts List" style="zoom:33%;" />

### Detailed Alert Drill-Down

<img src="./images/Alert Details.png" alt="Alert Details" style="zoom:33%;" />

### Alert Statistics & Operational Insights

<img src="./images/Alert Statistics.png" alt="Alert Statistics" style="zoom: 33%;" />



## **The Technical Architecture**

The end-to-end data flow:

<img src="./images/health_care technical architecture.svg" alt="health_care technical architecture" style="zoom: 25%;" />

### **1. Data Capture (Medical Devices → Kafka)**

- Medical devices (wearables, bedside monitors) stream real-time vital sign data (JSON format) to Kafka topics. Each message includes patient ID, device ID, timestamp, and vital sign values.

A lightweight Python producer (included in the demo) simulates device data for testing, generating normal and abnormal readings to trigger alerts.

### **2. Streaming Processing (RisingWave)**

**Step 1: Ingest Data from Kafka**

With a single `CREATE SOURCE` command, RisingWave ingests the Kafka stream and makes it queryable as a Source Table:

```sql
CREATE SOURCE patient_vital_signs_stream (
    patient_id STRING,          -- Unique identifier for patient (inpatient number)
    device_id STRING,           -- Monitoring device ID (serial number)
    measure_time TIMESTAMP,     -- Measurement time (accurate to milliseconds)
    heart_rate INT,             -- Heart rate (beats per minute)
    blood_oxygen DECIMAL,       -- Blood oxygen saturation (%)
    blood_glucose DECIMAL       -- Blood glucose level (mmol/L)
) WITH (
    connector = 'kafka',
    topic = 'vital_signs',
    properties.bootstrap.server = 'localhost:9092'
) FORMAT PLAIN ENCODE JSON;
```

**Step 2: Detect Anomalies with SQL**

We can customize alert rules and create a materialized view to track alerts in real time:

```sql
CREATE MATERIALIZED VIEW vital_signs_single_alerts AS
SELECT
    v.patient_id AS patient_id,
    v.measure_time AS measure_time,
    CASE
        WHEN v.heart_rate < t.heart_rate_min OR v.heart_rate > t.heart_rate_max THEN 'heart_rate'
        WHEN v.blood_oxygen < t.blood_oxygen_min THEN 'blood_oxygen'
        WHEN v.blood_glucose < t.blood_glucose_min OR v.blood_glucose > t.blood_glucose_max THEN 'blood_glucose'
        END AS "alert_type",
    CASE
        WHEN v.heart_rate < t.heart_rate_min THEN CONCAT('Heart rate too low: ', v.heart_rate, ' bpm')
        WHEN v.heart_rate > t.heart_rate_max THEN CONCAT('Heart rate too high: ', v.heart_rate, ' bpm')
        WHEN v.blood_oxygen < t.blood_oxygen_min THEN CONCAT('Blood oxygen too low: ', v.blood_oxygen, '%')
        WHEN v.blood_glucose < t.blood_glucose_min THEN CONCAT('Blood glucose too low: ', v.blood_glucose, ' mmol/L')
        WHEN v.blood_glucose > t.blood_glucose_max THEN CONCAT('Blood glucose too high: ', v.blood_glucose, ' mmol/L')
        END AS "alert_detail"
FROM patient_vital_signs_stream v
         LEFT JOIN vital_signs_thresholds t ON v.patient_id = t.patient_id
WHERE
    (v.heart_rate < t.heart_rate_min OR v.heart_rate > t.heart_rate_max)
   OR (v.blood_oxygen < t.blood_oxygen_min)
   OR (v.blood_glucose < t.blood_glucose_min OR v.blood_glucose > t.blood_glucose_max);
```

**Step 3: Sink Processed Data to The Hospital Databases**

To connect stream-processed alerts to the hospital databases (e.g., MySQL), we use RisingWave’s `CREATE SINK` command to real-time sync the materialized view data to it.

```sql
CREATE SINK alerts_sink FROM unified_alerts
WITH (
    connector='jdbc',
    jdbc.url='jdbc:mysql://localhost:3306/medical_alerts',
    user='root',
    password='root',
    table.name='alerts',
    type = 'append-only',
    force_append_only='true',
    primary_key = 'alert_id'
);
```

### **3. Real-Time Visualization (Frontend Dashboard)**

The frontend dashboard is built with **HTML5 + Tailwind CSS + JavaScript**—aligning with the demo’s lightweight, production-ready design principles. It interacts with the backend via a FastAPI service that reads synced alert data from MySQL.
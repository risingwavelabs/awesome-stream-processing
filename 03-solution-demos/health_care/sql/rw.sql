-- Set time zone to Asia/Shanghai
SET TIME ZONE 'Asia/Shanghai';

-- Drop existing objects (if exists) to avoid conflicts
DROP SINK IF EXISTS alerts_sink;

DROP MATERIALIZED VIEW IF EXISTS unified_alerts;

DROP MATERIALIZED VIEW IF EXISTS vital_signs_single_alerts;
DROP MATERIALIZED VIEW IF EXISTS vital_signs_trend_alerts;

DROP SOURCE IF EXISTS patient_vital_signs_stream;
DROP TABLE IF EXISTS vital_signs_thresholds;

-- Create Kafka source for real-time patient vital signs data
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

-- Create table for patient-specific vital signs thresholds
CREATE TABLE vital_signs_thresholds (
    threshold_id INT PRIMARY KEY,
    patient_id VARCHAR,
    disease_type VARCHAR,
    heart_rate_min INT DEFAULT 50,    -- Minimum normal heart rate
    heart_rate_max INT DEFAULT 120,    -- Maximum normal heart rate
    blood_oxygen_min DECIMAL DEFAULT 93.00,  -- Minimum normal blood oxygen saturation
    blood_glucose_min DECIMAL DEFAULT 3.90,   -- Minimum normal blood glucose level
    blood_glucose_max DECIMAL DEFAULT 7.20,   -- Maximum normal blood glucose level
    update_by VARCHAR DEFAULT 'admin',        -- User who updated the threshold
    update_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP()  -- Threshold update time
);

-- Insert default thresholds for general patients
INSERT INTO vital_signs_thresholds (threshold_id, patient_id, disease_type)
VALUES (1, 'P001', 'general'),
       (2, 'P002', 'general'),
       (3, 'P003', 'general');

-- Create materialized view for single-index abnormal alerts (level 1)
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
        END AS "alert_detail",
    'level1' AS alert_level,
    MD5(CONCAT(v.patient_id, v.measure_time)) AS alert_id
FROM patient_vital_signs_stream v
         LEFT JOIN vital_signs_thresholds t ON v.patient_id = t.patient_id
WHERE
    (v.heart_rate < t.heart_rate_min OR v.heart_rate > t.heart_rate_max)
   OR (v.blood_oxygen < t.blood_oxygen_min)
   OR (v.blood_glucose < t.blood_glucose_min OR v.blood_glucose > t.blood_glucose_max);

-- Create materialized view for multi-index trend deterioration alerts (level 2)
CREATE MATERIALIZED VIEW vital_signs_trend_alerts AS
WITH w AS (
    SELECT  patient_id,
            LAST_VALUE(heart_rate ORDER BY measure_time) - FIRST_VALUE(heart_rate ORDER BY measure_time) AS heart_rate_increase,
            FIRST_VALUE(blood_oxygen ORDER BY measure_time) - LAST_VALUE(blood_oxygen ORDER BY measure_time) AS blood_oxygen_decrease,
            window_end
    FROM TUMBLE(patient_vital_signs_stream, measure_time, '10 MINUTES')
    GROUP BY patient_id, window_end
)
SELECT
    patient_id,
    window_end AS measure_time,
    'multi_vital_signs_deterioration' AS alert_type,
    heart_rate_increase,
    blood_oxygen_decrease,
    'level2' AS alert_level,
    MD5(CONCAT(patient_id, window_end, 'multi_vital_signs_deterioration')) AS alert_id
FROM w
WHERE heart_rate_increase >= 20 AND blood_oxygen_decrease >= 5;

-- Create unified alerts view with 30-second deduplication (keep latest alert per patient/type)
CREATE MATERIALIZED VIEW unified_alerts AS
WITH latest_alerts AS (
    SELECT
      patient_id,
      measure_time,
      alert_type,
      alert_detail,
      alert_level,
      alert_id
    FROM vital_signs_single_alerts
    UNION ALL
    SELECT
      patient_id,
      measure_time,
      alert_type,
      CONCAT('Heart rate increased by ', heart_rate_increase, ' bpm and blood oxygen decreased by ', blood_oxygen_decrease, '% in 10 minutes') AS alert_detail,
      alert_level,
      alert_id
    FROM vital_signs_trend_alerts
)
SELECT DISTINCT ON (patient_id, alert_type, DATE_TRUNC('second', measure_time) - INTERVAL '30 seconds' * (EXTRACT(SECOND FROM measure_time)::INT / 30))
    patient_id,
    measure_time AS alert_time,
    alert_type,
    alert_detail,
    alert_level,
    alert_id
FROM latest_alerts;

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

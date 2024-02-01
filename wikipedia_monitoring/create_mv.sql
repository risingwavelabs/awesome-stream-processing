-- It creates "wiki_mv" that extracts columns from the "wiki_source", casting data types and filters out records with null timestamps, registrations, and edit counts.
  
CREATE MATERIALIZED VIEW wiki_mv AS
SELECT  
  contributor,
  title,
  CAST(edit_timestamp AS TIMESTAMP) AS edit_timestamp,
  CAST(registration AS TIMESTAMP) AS registration,
  gender,
  CAST(edit_count AS INT) AS edit_count
FROM wiki_source
WHERE timestamp IS NOT NULL
  AND registration IS NOT NULL
  AND edit_count IS NOT NULL;

-- It creates "gender_mv" that counts contributions based on gender from the "wiki_mv" materialized view and uses a 1-minute tumbling window on edit timestamps.
  
CREATE MATERIALIZED VIEW gender_mv AS
SELECT COUNT(*) AS total_contributions,
COUNT(CASE WHEN gender = 'unknown' THEN 1 END) AS contributions_by_unknown,
COUNT(CASE WHEN gender != 'unknown' THEN 1 END) AS contributions_by_male_or_female,
window_start, window_end
FROM TUMBLE (wiki_mv, edit_timestamp, INTERVAL '1 MINUTES')
GROUP BY window_start, window_end;

-- It creates "registration_mv" that counts contributions based on the registration of contributors from the "wiki_mv" materialized view and uses a 1-minute tumbling window on edit timestamps.
  
CREATE MATERIALIZED VIEW registration_mv AS
SELECT COUNT(*) AS total_contributions,
COUNT(CASE WHEN registration < '2020-01-01 01:00:00'::timestamp THEN 1 END) AS contributions_by_someone_registered_before_2020,
COUNT(CASE WHEN registration > '2020-01-01 01:00:00'::timestamp THEN 1 END) AS contributions_by_someone_registered_after_2020,
 window_start, window_end
FROM TUMBLE (wiki_mv, edit_timestamp, INTERVAL '1 MINUTES')
GROUP BY window_start, window_end;

-- It creates "count_mv" that counts contributions based on the edit count of contributors from the "wiki_mv" materialized view and uses a 1-minute tumbling window on edit timestamps.

CREATE MATERIALIZED VIEW count_mv AS
SELECT 
    COUNT(*) AS total_contributions,
    COUNT(CASE WHEN edit_count < 1000 THEN 1 END) AS contributions_less_than_1000,
    COUNT(CASE WHEN edit_count >= 1000 THEN 1 END) AS contributions_1000_or_more,
    window_start, window_end
FROM TUMBLE(wiki_mv, edit_timestamp, INTERVAL '1 MINUTES')
GROUP BY window_start, window_end;

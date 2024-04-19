# Process and transform data in RisingWave

Now that the sources in RisingWave are set up, we can create some materialized views. The sources and tables in RisingWave do not ingest any data; they only connect to the data stream. In order to ingest, process, and persist the data in RisingWave, we need materialized views. The materialized views continuously, incrementally compute the ingested data.

We will create a materialized view that tracks how many actions each user performs on each web page within a three minute window.

The following SQL query tracks how many action each user performs on each webpage within a three minute window by employing the `TUMBLE` function by creating a materialized view called `tumbled`. The `EMIT ON WINDOW CLOSE` clause is also used so the materialized view emits a new row result at the end of each window frame. This clause can be used since the `site_visits` source was defined with a watermark.

```sql
CREATE MATERIALIZED VIEW tumbled AS
SELECT user_id, page_id, COUNT(action) AS num_actions, window_end 
FROM TUMBLE (site_visits, action_time, INTERVAL '3' MINUTE)
GROUP BY user_id, page_id, window_end
EMIT ON WINDOW CLOSE;
```

The results may look like this.

```
 user_id | page_id | num_actions |        window_end         
---------+---------+-------------+---------------------------
       1 |       1 |           1 | 2024-04-19 21:21:00+00:00
       1 |       2 |           1 | 2024-04-19 21:09:00+00:00
       1 |       2 |           1 | 2024-04-19 23:09:00+00:00
       1 |       2 |           7 | 2024-04-19 23:12:00+00:00
       1 |       3 |           1 | 2024-04-19 20:57:00+00:00

```

Next, we will join the `tumbled` materialized view with the `users` table from PostgreSQL to gain additional information on each user. 

```sql
CREATE MATERIALIZED VIEW website_visits_1min AS
SELECT user_id, first_name, last_name, age, page_id, num_actions, window_end
FROM tumbled 
LEFT JOIN users ON users.id = mv1.user_id;
```

The results may look like this. 

```
 user_id | first_name | last_name | age | page_id | num_actions |        window_end         
---------+------------+-----------+-----+---------+-------------+---------------------------
       1 | John       | Smith     |  28 |       3 |           5 | 2024-04-19 23:15:00+00:00
       1 | John       | Smith     |  28 |      12 |           4 | 2024-04-19 23:15:00+00:00
       1 | John       | Smith     |  28 |       6 |           5 | 2024-04-19 23:15:00+00:00
       2 | Emma       | Johnson   |  34 |       5 |           4 | 2024-04-19 23:15:00+00:00
       1 | John       | Smith     |  28 |       9 |           3 | 2024-04-19 23:15:00+00:00
```


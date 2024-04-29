# Process and transform data in RisingWave

Now that the sources in RisingWave are set up, we can create some materialized views. The sources in RisingWave do not ingest any data; they only connect to the data stream. In order to ingest, process, and persist the data in RisingWave, we need materialized views. The materialized views continuously, incrementally compute the ingested data.

## Create a materialized view

We will create a materialized view, `website_visits_1min`, that tracks how many actions each user performs on each web page within a three minute window.

The following SQL query uses the `tumble` function to map events into three-minute windows, then groups by `user_id`, `page_id`, and `window_end` to count the number of actions each user performs on each web page within the designated time window. Finally, we join the resulting table with the `users` table to see the corresponding `first_name`, `last_name`, and `age` of each user. 

```sql
CREATE MATERIALIZED VIEW website_visits_1min AS
SELECT user_id, first_name, last_name, age, page_id, num_actions, window_end
FROM
    (SELECT user_id, page_id, COUNT(action) AS num_actions, window_end 
    FROM TUMBLE (mv1, action_time, INTERVAL '3' MINUTE)
    GROUP BY user_id, page_id, window_end) t
LEFT JOIN users ON t.user_id = users.user_id;
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



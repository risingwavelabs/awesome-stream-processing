-- This sink ends passenger check-in notifications for flights departing within 48 to 72 hours to an MQTT broker, using the topic checkin_open_notification and delivering messages in JSON format with at-least-once quality of service.
CREATE SINK checkin_notifications_sink
FROM checkin_open_notification
WITH (
    connector = 'mqtt',
    topic = 'checkin_open_notification',
    url = 'ssl://xxxxxxxxxx:8883',
    username='solace-cloud-client',
    password='xxxxxxxxxxxx', 
     type = 'append-only',
    qos = 'at_least_once'
    ) FORMAT PLAIN ENCODE JSON (
   force_append_only='true',
   );

-- This sink publishes alerts for flights with a "Meal Shortage" status to an MQTT broker via the topic meal_shortage_alert, encoding messages in JSON format and ensuring at-least-once message delivery.
CREATE SINK meal_shortage_alert_sink
FROM meal_shortage_alert
WITH (
    connector = 'mqtt',
    topic = 'meal_shortage_alert',
    url = 'ssl://xxxxxxxxxx:8883',
    username='solace-cloud-client',
    password='xxxxxxxxxxxx', 
    type = 'append-only',
    qos = 'at_least_once'
    ) FORMAT PLAIN ENCODE JSON (
   force_append_only='true',
);
   

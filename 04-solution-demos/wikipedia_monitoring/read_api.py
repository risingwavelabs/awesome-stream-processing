from kafka import KafkaProducer
import json
import requests
import time

# Kafka topic to produce messages to


def get_user_contributions(user):
    endpoint = "https://en.wikipedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "list": "usercontribs",
        "ucuser": user,
        "uclimit": 1,
        "ucprop": "title|timestamp",
    }

    response = requests.get(endpoint, params=params)
    data = response.json()

    if "query" in data and "usercontribs" in data["query"]:
        return data["query"]["usercontribs"]

    return None

def get_user_info(user):
    endpoint = "https://en.wikipedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "list": "users",
        "ususers": user,
        "usprop": "registration|gender|editcount|groups|rights|emailable|centralids",
    }

    response = requests.get(endpoint, params=params)
    data = response.json()

    if "query" in data and "users" in data["query"]:
        return data["query"]["users"][0]

    return None

def get_recent_changes():
    endpoint = "https://en.wikipedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "list": "recentchanges",
        "rcprop": "user|title|timestamp",
        "rclimit": 1,
    }

    response = requests.get(endpoint, params=params)
    data = response.json()

    if "query" in data and "recentchanges" in data["query"]:
        return data["query"]["recentchanges"]

    return None


def track_changes():
    print("Tracking Wikipedia Changes:")
    while True:
        recent_changes = get_recent_changes()

        if recent_changes:
            for change in recent_changes:
                user = change.get("user", "")
                user_contributions = get_user_contributions(user)

                if user_contributions:
                    contribution = user_contributions[0]
                    title = contribution.get("title", "")
                    timestamp = contribution.get("timestamp", "")


                    print(f"User: {user}, Title: {title}, Timestamp: {timestamp}")

                    user_info = get_user_info(user)
                    if user_info:
                        registration = user_info.get("registration", "")


                        gender = user_info.get("gender", "")
                        edit_count = user_info.get("editcount", "")



                        print(f"Registration: {registration}, Gender: {gender}, Edit Count: {edit_count}")

                        # Prepare the message as a dictionary
                        kafka_message = {
                            "contributor": user,
                            "title": title,
                            "timestamp": timestamp,
                            "registration": registration,
                            "gender": gender,
                            "edit_count": edit_count
                        }
                        
                        producer = KafkaProducer(api_version=(0, 10, 1),bootstrap_servers= ['kafka:9092'])

                        topic = 'live_wikipedia_data'

                        # Convert the message to JSON and produce it to the Kafka topic
                        producer.send(topic, json.dumps(kafka_message).encode('utf-8'))
                        producer.flush()


        time.sleep(1)

if __name__ == "__main__":
    track_changes()
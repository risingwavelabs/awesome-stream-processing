from kafka import KafkaProducer
import json
import requests
import time

# Kafka topic to produce messages to
topic = 'flights_tracking'

# Kafka producer
producer = KafkaProducer(api_version=(0, 10, 1),bootstrap_servers= ['kafka:9092'])

# Replace with your Aviationstack API key
api_key = "17582ef651bce84bcebe9fcee10efb6d"

# Base URL for Aviationstack API
base_url = "http://api.aviationstack.com/v1/flights"

# Number of records to fetch
records_to_fetch = 5

params = {
    "access_key": api_key,
    'limit': records_to_fetch,
}

flight_info = ""
# Send API request and get response
response = requests.get(base_url, params=params)

# Check for successful response
if response.status_code == 200:
    # Convert JSON response to dictionary
    result = response.json()
    print(result)


    # Loop through each record in the response
    for data_field in result["data"]:
        # Extract information from the response
        flight_date = data_field['flight_date']
        flight_status = data_field['flight_status']


        departure_airport = data_field['departure']['airport']
        departure_timezone =data_field ['departure']['timezone']
        departure_iata = data_field['departure']['iata']
        departure_icao = data_field['departure']['icao']
        departure_terminal = data_field['departure']['terminal']
        departure_gate = data_field['departure']['gate']
        departure_delay = data_field['departure']['delay']
        departure_scheduled = data_field['departure']['scheduled']
        departure_estimated = data_field['departure']['estimated']
        departure_actual = data_field['departure']['actual']
        departure_estimated_runway = data_field['departure']['estimated_runway']
        departure_actual_runway = data_field['departure']['actual_runway']


        arrival_airport = data_field['arrival']['airport']
        arrival_timezone = data_field['arrival']['timezone']
        arrival_iata = data_field['arrival']['iata']
        arrival_icao = data_field['arrival']['icao']
        arrival_terminal = data_field['arrival']['terminal']
        arrival_gate = data_field['arrival']['gate']
        arrival_baggage = data_field['arrival']['baggage']
        arrival_delay = data_field['arrival']['delay']
        arrival_scheduled = data_field['arrival']['scheduled']
        arrival_estimated = data_field['arrival']['estimated']
        arrival_actual = data_field['arrival']['actual']
        arrival_estimated_runway = data_field['arrival']['estimated_runway']
        arrival_actual_runway = data_field['arrival']['actual_runway']


        airline_name = data_field['airline']['name']
        airline_iata = data_field['airline']['iata']
        airline_icao = data_field['airline']['icao']


        flight_number = data_field['flight']['number']
        flight_iata = data_field['flight']['iata']
        flight_icao = data_field['flight']['icao']

        if data_field['flight']['codeshared'] is not None:
           codeshared_airline_name = data_field['flight']['codeshared']['airline_name']
           codeshared_airline_iata = data_field['flight']['codeshared']['airline_iata']
           codeshared_airline_icao = data_field['flight']['codeshared']['airline_icao']
           codeshared_flight_number = data_field['flight']['codeshared']['flight_number']
           codeshared_flight_iata = data_field['flight']['codeshared']['flight_iata']

        else:
           codeshared_airline_name = "null"
           codeshared_airline_iata = "null"
           codeshared_airline_icao = "null"
           codeshared_flight_number = "null"
           codeshared_flight_iata = "null"

        airline_name = data_field["airline"]["name"]
        flight_number = data_field["flight"]["iata"]
        departure_airport = data_field["departure"]["airport"]
        departure_iata = data_field["departure"]["iata"]
        arrival_airport = data_field["arrival"]["airport"]
        arrival_iata = data_field["arrival"]["iata"]

        # Concatenate flight information to the variable
        flight_info = f"{airline_name} flight {flight_number} is currently in the air, " \
                       f"flying from {departure_airport} ({departure_iata}) to " \
                       f"{arrival_airport} ({arrival_iata})"

        # Create a flattened dictionary with the extracted information
        flight_data_flat = {
        "flight_date": flight_date,
        "flight_status": flight_status,
        "departure_airport": departure_airport,
        "departure_timezone": departure_timezone,
        "departure_iata": departure_iata,
        "departure_icao": departure_icao,
        "departure_terminal": departure_terminal,
        "departure_gate": departure_gate,
        "departure_delay": departure_delay,
        "departure_scheduled": departure_scheduled,
        "departure_estimated": departure_estimated,
        "departure_actual": departure_actual,
        "departure_estimated_runway": departure_estimated_runway,
        "departure_actual_runway": departure_actual_runway,
        "arrival_airport": arrival_airport,
        "arrival_timezone": arrival_timezone,
        "arrival_iata": arrival_iata,
        "arrival_icao": arrival_icao,
        "arrival_terminal": arrival_terminal,
        "arrival_gate": arrival_gate,
        "arrival_baggage": arrival_baggage,
        "arrival_delay": arrival_delay,
        "arrival_scheduled": arrival_scheduled,
        "arrival_estimated": arrival_estimated,
        "arrival_actual": arrival_actual,
        "arrival_estimated_runway": arrival_estimated_runway,
        "arrival_actual_runway": arrival_actual_runway,
        "airline_name": airline_name,
        "airline_iata": airline_iata,
        "airline_icao": airline_icao,
        "flight_number": flight_number,
        "flight_iata": flight_iata,
        "flight_icao": flight_icao,
        "codeshared_airline_name": codeshared_airline_name,
        "codeshared_airline_iata": codeshared_airline_iata,
        "codeshared_airline_icao": codeshared_airline_icao,
        "codeshared_flight_number": codeshared_flight_number,
        "codeshared_flight_iata": codeshared_flight_iata,
        "flight_info": flight_info
        }

        # Convert the flattened dictionary to JSON
        flight_data_flat_json = json.dumps(flight_data_flat, indent=2)

        # Print or use the JSON as needed
        print(flight_data_flat_json)

        # Produce the JSON message to the Kafka topic
        producer.send(topic, flight_data_flat_json.encode('utf-8'))
        flight_info = ""
        # Sleep for a short duration to avoid rate limiting (adjust as needed)
        time.sleep(1)

    # Flush Kafka producer
    producer.flush()

else:
    print(f"Error: {response.status_code}")
    exit(1)
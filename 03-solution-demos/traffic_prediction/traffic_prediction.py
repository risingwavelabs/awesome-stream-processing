import json
import time
import numpy as np
import pandas as pd
from kafka import KafkaProducer
from keras.src.saving import load_model
from snowflake import SnowflakeGenerator
from risingwave import RisingWave, RisingWaveConnOptions, OutputFormat
from sklearn.preprocessing import MinMaxScaler

# Connect to RisingWave instance on localhost with named parameters
rw = RisingWave(
    RisingWaveConnOptions.from_connection_info(
        host="localhost", port=4566, user="root", password="root", database="dev"
    )
)

producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

roads = 4
time_step = 5
features = 2

idgen = SnowflakeGenerator(50)

def fetch_features():
    data = rw.fetch(f"""
                            SELECT *
                            FROM features_last_5min
                            ORDER BY road_id, window_start;
                            """)
    return np.array(data)

sc = MinMaxScaler(feature_range=(0, 1))

def dataformat_transform(data):
    data = data[:, 2:4].astype(float) # (20, 2)
    data_sc = sc.fit_transform(data)
    data_sc = np.reshape(data_sc, [4, 5, 2]) # (4, 5, 2)
    return data_sc

def inv_transform(arr):
    arr_full = np.zeros((arr.shape[0], features))
    arr_full[:, 0] = arr[:, 0]
    return sc.inverse_transform(arr_full)[:, 0]

lstm_model = load_model('model/traffic_prediction_model.keras')

while True:
    data = fetch_features() # (20, 4)
    length = len(data)

    if length > 0:
        pre_flow = []

        if length == roads * time_step:
            data_sc = dataformat_transform(data)

            pre_flow = lstm_model.predict(data_sc)
            pre_flow = inv_transform(pre_flow)
            print(pre_flow)

            for i in range(roads):
                print(f"The predicted traffic flow of road {i} is {pre_flow[i]}")

        display_data = []
        for i in range(roads):
            road_data = data[(i + 1) * length // roads - 1]

            traffic_flow_data = {
                "id": next(idgen),
                "road_id": road_data[0],
                "datetime": road_data[1].isoformat(),
                "traffic_flow": road_data[2],
                "avg_speed_kph": road_data[3],
                "predicted_flow_next_minute": pre_flow[i] if len(pre_flow) > 0 else None,
            }
            print(traffic_flow_data)
            producer.send('traffic-flow', traffic_flow_data)

            fetched_data = rw.fetch(f"select * from history_flow where road_id = 'R{i + 1}' order by datetime desc", format=OutputFormat.DATAFRAME)
            fetched_data['datetime'] = fetched_data['datetime'].astype(str)
            display_data.append(fetched_data.where(pd.notnull(fetched_data), "nan").to_dict(orient="records"))

        if len(display_data[0]) > 0:
            print(display_data)
            producer.send('data-display', display_data)
    time.sleep(60)

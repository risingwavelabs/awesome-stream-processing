FROM python:3.8

RUN pip install paho-mqtt

COPY send_data_mqtt.py /app/send_data_mqtt.py

WORKDIR /app

CMD ["python", "send_data_mqtt.py"]

FROM python:3.8

RUN pip install kafka-python Faker

COPY data_send.py /app/data_send.py
COPY datagen.py /app/datagen.py

WORKDIR /app

CMD ["python", "data_send.py"]

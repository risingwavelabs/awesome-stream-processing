FROM python:3.8

RUN pip install kafka

COPY read_api.py /app/read_api.py

WORKDIR /app

CMD ["python", "read_api.py"]
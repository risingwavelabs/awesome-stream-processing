FROM python:3.8

RUN pip install kafka-python requests
RUN sleep 3
# Create a directory for the Python files
WORKDIR /app

# Copy Python files into the container
COPY flink_producer/run_producers.py .
COPY flink_producer/constant_data.py .
COPY flink_producer/varying_data.py .

# Run the Python script
CMD ["python", "run_producers.py"]
FROM python:3.8

RUN pip install kafka-python faker

# Create a directory for the Python files
WORKDIR /app

# Copy Python files into the container
COPY data-producers/run-producers.py .
COPY data-producers/restocks.py .
COPY data-producers/purchases.py .

# Run the Python script
CMD ["python", "run-producers.py"]
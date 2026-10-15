FROM python:3.9-slim

WORKDIR /app

COPY ./requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ./traffic_monitor_service.py .

EXPOSE 8000 8001

CMD ["python", "traffic_monitor_service.py"]
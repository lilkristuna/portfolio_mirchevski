FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install aiokafka fastapi scikit-learn prometheus-client aiohttp numpy uvicorn
EXPOSE 8002 8003

CMD ["python", "security_analyzer_service.py"]
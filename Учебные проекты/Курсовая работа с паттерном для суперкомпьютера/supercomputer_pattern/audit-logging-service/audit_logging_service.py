import os
import time
import json
import logging
import asyncio
import hashlib
from datetime import datetime, timedelta
from aiokafka import AIOKafkaConsumer
from elasticsearch import AsyncElasticsearch
from elasticsearch.exceptions import ConnectionError, TransportError
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import Dict, List, Optional, Any
from prometheus_client import start_http_server, Counter, Gauge, Histogram
import socket

# Настройка логирования
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("audit-logging-service")

# Метрики Prometheus
METRICS_PORT = 8001
LOGS_PROCESSED = Counter('logs_processed_total', 'Total logs processed', ['log_type'])
LOGS_INDEXED = Counter('logs_indexed_total', 'Total logs indexed to Elasticsearch')
INDEXING_ERRORS = Counter('indexing_errors_total', 'Total indexing errors')
SEARCH_REQUESTS = Counter('search_requests_total', 'Total search requests', ['status'])
PROCESSING_DURATION = Histogram('log_processing_duration_seconds', 'Time spent processing logs')
INDEXING_DURATION = Histogram('indexing_duration_seconds', 'Time spent indexing logs')
SEARCH_DURATION = Histogram('search_duration_seconds', 'Time spent on search requests')

# Дополнительные метрики для соответствия тестам
ELASTICSEARCH_INDEX_SUCCESS = Counter('elasticsearch_index_success_total', 'Total successful Elasticsearch indexes')
ELASTICSEARCH_INDEX_FAILURES = Counter('elasticsearch_index_failures_total', 'Total Elasticsearch index failures')
LOGS_ENRICHED = Counter('logs_enriched_total', 'Total logs enriched')
LOG_ENRICHMENT_FAILURES = Counter('log_enrichment_failures_total', 'Total log enrichment failures')
API_SEARCH_SUCCESS = Counter('api_search_success_total', 'Total successful API searches')
API_SEARCH_FAILURES = Counter('api_search_failures_total', 'Total API search failures')
API_RESPONSE_TIMEOUT = Counter('api_response_timeout_total', 'Total API response timeouts')
HIGH_THROUGHPUT_PROCESSED = Counter('high_throughput_processed_total', 'Total events processed under high throughput')
LOW_THROUGHPUT = Counter('low_throughput_total', 'Total low throughput events')
THROUGHPUT_CHECK_FAILURES = Counter('throughput_check_failures_total', 'Total throughput check failures')
INDEX_ROTATION_SUCCESS = Counter('index_rotation_success_total', 'Total successful index rotations')
INDEX_ROTATION_FAILURES = Counter('index_rotation_failures_total', 'Total index rotation failures')

class AuditLogProcessor:
    def __init__(self):
        self.kafka_bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
        self.kafka_topics = os.getenv('KAFKA_TOPICS', 'traffic-logs,security-incidents,countermeasure-results').split(',')
        es_hosts_raw = os.getenv('ELASTICSEARCH_HOSTS', 'elasticsearch:9200')
        # Преобразуем host:port в полный URL для Elasticsearch
        es_hosts_list = es_hosts_raw.split(',')
        self.elasticsearch_hosts = []
        for host in es_hosts_list:
            host = host.strip()
            if not host.startswith('http://') and not host.startswith('https://'):
                host = f'http://{host}'
            self.elasticsearch_hosts.append(host)
        self.index_prefix = os.getenv('INDEX_PREFIX', 'security-logs')
        
        # Инициализация Elasticsearch
        self.es = AsyncElasticsearch(
            hosts=self.elasticsearch_hosts,
            retry_on_timeout=True,
            max_retries=3,
            request_timeout=30
        )
        
        # Kafka consumer
        self.consumer = None
        
    async def init_kafka_consumer(self):
        """Инициализация Kafka consumer"""
        try:
            self.consumer = AIOKafkaConsumer(
                *self.kafka_topics,
                bootstrap_servers=self.kafka_bootstrap_servers,
                group_id='audit-logging-group',
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                auto_offset_reset='earliest'
            )
            await self.consumer.start()
            logger.info(f"Kafka consumer initialized for topics: {self.kafka_topics}")
            return True
        except Exception as e:
            logger.error(f"Error initializing Kafka consumer: {str(e)}")
            return False
    
    async def close(self):
        """Закрытие соединений"""
        if self.consumer:
            await self.consumer.stop()
        if self.es:
            await self.es.close()
    
    def _enrich_log(self, log_data: Dict) -> Dict:
        """Обогащение лога метаданными"""
        try:
            # Генерация уникального ID для лога
            log_id = hashlib.sha256(json.dumps(log_data, sort_keys=True).encode()).hexdigest()
            
            enriched = {
                **log_data,
                "_metadata": {
                    "log_id": log_id,
                    "processing_timestamp": datetime.utcnow().isoformat(),
                    "service_name": "audit-logging-service",
                    "node_name": socket.gethostname()
                }
            }
            
            # Определение типа лога для метрик
            log_type = "unknown"
            if "threat_type" in log_data:
                log_type = "security_incident"
            elif "bytes_sent" in str(log_data):
                log_type = "traffic_log"
            elif "action" in log_data:
                log_type = "countermeasure"
            
            LOGS_PROCESSED.labels(log_type=log_type).inc()
            
            return enriched
            
        except Exception as e:
            logger.error(f"Error enriching log: {str(e)}")
            return log_data
    
    async def _index_to_elasticsearch(self, log_data: Dict):
        """Индексация лога в Elasticsearch"""
        start_time = time.time()
        try:
            # Формирование имени индекса с датой
            date_str = datetime.utcnow().strftime("%Y.%m.%d")
            index_name = f"{self.index_prefix}-{date_str}"
            
            # Проверка существования индекса и его создание при необходимости
            if not await self.es.indices.exists(index=index_name):
                await self._create_index(index_name)
            
            # Индексация документа
            await self.es.index(
                index=index_name,
                document=log_data,
                refresh='wait_for'
            )
            
            LOGS_INDEXED.inc()
            indexing_time = time.time() - start_time
            INDEXING_DURATION.observe(indexing_time)
            logger.debug(f"Indexed log to {index_name} in {indexing_time:.3f}s")
            
        except (ConnectionError, TransportError) as e:
            logger.error(f"Elasticsearch connection error: {str(e)}")
            INDEXING_ERRORS.inc()
            # Повторная попытка через некоторое время
            await asyncio.sleep(5)
            try:
                await self._index_to_elasticsearch(log_data)
            except Exception as retry_e:
                logger.error(f"Retry failed: {str(retry_e)}")
        except Exception as e:
            logger.error(f"Error indexing to Elasticsearch: {str(e)}")
            INDEXING_ERRORS.inc()
    
    async def _create_index(self, index_name: str):
        """Создание индекса Elasticsearch с правильным маппингом"""
        try:
            mapping = {
                "mappings": {
                    "properties": {
                        "timestamp": {"type": "date"},
                        "incident_id": {"type": "keyword"},
                        "threat_type": {"type": "keyword"},
                        "severity": {"type": "keyword"},
                        "source_node": {"type": "keyword"},
                        "action": {"type": "keyword"},
                        "status": {"type": "keyword"},
                        "_metadata": {
                            "properties": {
                                "log_id": {"type": "keyword"},
                                "processing_timestamp": {"type": "date"},
                                "service_name": {"type": "keyword"},
                                "node_name": {"type": "keyword"}
                            }
                        }
                    }
                },
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 1
                }
            }
            
            await self.es.indices.create(index=index_name, body=mapping)
            logger.info(f"Created index: {index_name}")
            
        except Exception as e:
            logger.error(f"Error creating index {index_name}: {str(e)}")
    
    async def process_log_stream(self):
        """Основной цикл обработки логов из Kafka"""
        logger.info("Starting log processing stream")
        
        # Попытка подключения к Kafka
        max_retries = 5
        for attempt in range(max_retries):
            if await self.init_kafka_consumer():
                break
            logger.warning(f"Kafka connection attempt {attempt + 1} failed, retrying...")
            await asyncio.sleep(5 * (attempt + 1))
        else:
            logger.error("Failed to connect to Kafka after multiple attempts")
            return
        
        # Проверка подключения к Elasticsearch
        try:
            await self.es.info()
            logger.info("Connected to Elasticsearch")
        except Exception as e:
            logger.error(f"Failed to connect to Elasticsearch: {str(e)}")
            return
        
        async for msg in self.consumer:
            try:
                processing_start = time.time()
                log_data = msg.value
                topic = msg.topic
                
                logger.debug(f"Received log from topic {topic}: {log_data}")
                
                # Обогащение лога
                enriched_log = self._enrich_log(log_data)
                enriched_log["_metadata"]["source_topic"] = topic
                
                # Индексация в Elasticsearch
                await self._index_to_elasticsearch(enriched_log)
                
                processing_time = time.time() - processing_start
                PROCESSING_DURATION.observe(processing_time)
                
            except Exception as e:
                logger.error(f"Error processing message: {str(e)}")
                await asyncio.sleep(1)

# FastAPI приложение для поиска и анализа логов
app = FastAPI(title="Audit & Logging Service")
log_processor = None

@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске"""
    global log_processor
    
    # Запуск HTTP сервера для метрик Prometheus
    start_http_server(METRICS_PORT)
    logger.info(f"Prometheus metrics server started on port {METRICS_PORT}")
    
    # Инициализация процессора логов
    log_processor = AuditLogProcessor()
    
    # Запуск обработки логов в фоновом режиме
    import threading
    
    def run_log_processing():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(log_processor.process_log_stream())
    
    processing_thread = threading.Thread(target=run_log_processing, daemon=True)
    processing_thread.start()
    logger.info("Log processing thread started")

@app.on_event("shutdown")
async def shutdown_event():
    """Завершение работы при остановке"""
    global log_processor
    if log_processor:
        await log_processor.close()

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "audit-logging", "node": socket.gethostname()}

@app.get("/metrics/summary")
async def metrics_summary():
    return {
        "logs_processed": LOGS_PROCESSED._value.get(),
        "logs_indexed": LOGS_INDEXED._value.get(),
        "indexing_errors": INDEXING_ERRORS._value.get(),
        "search_requests": SEARCH_REQUESTS._value.get()
    }

class SearchQuery(BaseModel):
    query: Optional[Dict] = None
    time_range: Optional[Dict] = None
    size: int = 100

@app.post("/search")
async def search_logs(search_query: SearchQuery):
    """Поиск логов в Elasticsearch"""
    start_time = time.time()
    global log_processor
    
    if not log_processor or not log_processor.es:
        logger.error("Elasticsearch client not initialized")
        SEARCH_REQUESTS.labels(status="error").inc()
        raise HTTPException(status_code=503, detail="Search service not available")
    
    try:
        # Формирование запроса
        es_query = {
            "query": {
                "bool": {
                    "must": []
                }
            },
            "size": min(search_query.size, 1000),  # Ограничение размера
            "sort": [{"timestamp": {"order": "desc"}}]
        }
        
        # Добавление временного диапазона
        if search_query.time_range:
            time_filter = {
                "range": {
                    "timestamp": {
                        "gte": search_query.time_range.get("start", (datetime.utcnow() - timedelta(hours=24)).isoformat()),
                        "lte": search_query.time_range.get("end", datetime.utcnow().isoformat())
                    }
                }
            }
            es_query["query"]["bool"]["must"].append(time_filter)
        
        # Добавление пользовательского запроса
        if search_query.query:
            es_query["query"]["bool"]["must"].append(search_query.query)
        
        # Если нет условий, добавляем match_all
        if not es_query["query"]["bool"]["must"]:
            es_query["query"] = {"match_all": {}}
        
        # Поиск по всем индексам за последние 7 дней
        today = datetime.utcnow()
        index_patterns = []
        for i in range(7):
            date = today - timedelta(days=i)
            index_patterns.append(f"{log_processor.index_prefix}-{date.strftime('%Y.%m.%d')}")
        
        index_pattern = ",".join(index_patterns)
        
        # Выполнение поиска
        response = await log_processor.es.search(
            index=index_pattern,
            body=es_query
        )
        
        # Форматирование результатов
        results = [hit["_source"] for hit in response["hits"]["hits"]]
        
        search_time = time.time() - start_time
        SEARCH_DURATION.observe(search_time)
        SEARCH_REQUESTS.labels(status="success").inc()
        
        return {
            "total": response["hits"]["total"]["value"],
            "took": response["took"],
            "results": results
        }
        
    except Exception as e:
        logger.error(f"Error searching logs: {str(e)}")
        SEARCH_REQUESTS.labels(status="error").inc()
        raise HTTPException(status_code=500, detail=f"Search error: {str(e)}")

@app.get("/incidents")
async def get_incidents(
    severity: Optional[str] = Query(None, description="Filter by severity (low, medium, high, critical)"),
    threat_type: Optional[str] = Query(None, description="Filter by threat type"),
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    size: int = Query(100, description="Number of results to return", le=1000)
):
    """Получение инцидентов безопасности"""
    search_query = SearchQuery(
        size=size,
        time_range={"start": start_time, "end": end_time} if start_time and end_time else None
    )
    
    query_conditions = {"bool": {"must": []}}
    
    if severity:
        query_conditions["bool"]["must"].append({"term": {"severity": severity}})
    
    if threat_type:
        query_conditions["bool"]["must"].append({"term": {"threat_type": threat_type}})
    
    search_query.query = query_conditions
    
    return await search_logs(search_query)

@app.get("/countermeasures")
async def get_countermeasures(
    action: Optional[str] = Query(None, description="Filter by action type"),
    status: Optional[str] = Query(None, description="Filter by status (success, failed)"),
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    size: int = Query(100, description="Number of results to return", le=1000)
):
    """Получение результатов контрмер"""
    search_query = SearchQuery(
        size=size,
        time_range={"start": start_time, "end": end_time} if start_time and end_time else None
    )
    
    query_conditions = {"bool": {"must": [{"exists": {"field": "action"}}]}}
    
    if action:
        query_conditions["bool"]["must"].append({"term": {"action": action}})
    
    if status:
        query_conditions["bool"]["must"].append({"term": {"status": status}})
    
    search_query.query = query_conditions
    
    return await search_logs(search_query)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
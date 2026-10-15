import os
import time
import json
import asyncio
import logging
import numpy as np
from datetime import datetime
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from aiokafka.helpers import create_ssl_context
from sklearn.ensemble import IsolationForest
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict, Optional, Any
from prometheus_client import start_http_server, Counter, Gauge, Histogram
import socket
import aiohttp


logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("security-analyzer-service")


METRICS_PORT = 8003
FASTAPI_PORT = 8002
DETECTED_THREATS = Counter('detected_threats_total', 'Total detected threats', ['threat_type'])
ANALYZED_BATCHES = Counter('analyzed_batches_total', 'Total analyzed batches')
ANALYZER_ERRORS = Counter('analyzer_errors_total', 'Total errors in analysis')
ANALYSIS_DURATION = Histogram('analysis_duration_seconds', 'Time spent on analysis')
THREAT_SEVERITY_COUNT = Counter('threat_severity_count', 'Count of threats by severity', ['severity'])

MPI_FLOOD_DETECTED = Counter('mpi_flood_detected_total', 'Total MPI flood detections')
DETECTION_FAILURES = Counter('detection_failures_total', 'Total detection failures')
FALSE_POSITIVE = Counter('false_positive_total', 'Total false positives')
NORMAL_TRAFFIC_PROCESSED = Counter('normal_traffic_processed_total', 'Total normal traffic processed')
ML_INFERENCE_SUCCESS = Counter('ml_inference_success_total', 'Total successful ML inferences')
ML_INFERENCE_FAILURES = Counter('ml_inference_failures_total', 'Total ML inference failures')
PROCESSING_TIMEOUT = Counter('processing_timeout_total', 'Total processing timeouts')
ANALYSIS_COMPLETED = Counter('analysis_completed_total', 'Total completed analyses')
RATE_LIMIT_EXCEEDED = Counter('rate_limit_exceeded_total', 'Total rate limit exceeded events')
RATE_LIMIT_OK = Counter('rate_limit_ok_total', 'Total rate limit OK events')

class Incident(BaseModel):
    incident_id: str
    threat_type: str
    severity: str
    source_node: str
    timestamp: str
    metrics: Dict[str, Any]
    recommended_action: str

class ThreatAnalyzer:
    def __init__(self):
        self.kafka_bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
        self.input_topic = os.getenv('INPUT_TOPIC', 'mpi-traffic-metrics')
        self.output_topic = os.getenv('OUTPUT_TOPIC', 'security-incidents')
        self.policy_manager_url = os.getenv('POLICY_MANAGER_URL', 'http://policy-manager-service:8000')
        self.slurm_controller_url = os.getenv('SLURM_CONTROLLER_URL', 'http://slurm-controller:8000')
        self.sdn_controller_url = os.getenv('SDN_CONTROLLER_URL', 'http://sdn-controller:8000')
        
        self.model = IsolationForest(
            n_estimators=100,
            contamination=0.05,
            random_state=42,
            n_jobs=-1
        )
        self.is_trained = False
        
        self.consumer = None
        self.producer = None
        
    async def init_kafka(self):
        """Инициализация Kafka consumer и producer"""
        self.consumer = AIOKafkaConsumer(
            self.input_topic,
            bootstrap_servers=self.kafka_bootstrap_servers,
            group_id="security-analyzer-group",
            value_deserializer=lambda m: json.loads(m.decode('utf-8'))
        )
        
        self.producer = AIOKafkaProducer(
            bootstrap_servers=self.kafka_bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        
        await self.consumer.start()
        await self.producer.start()
        logger.info(f"Kafka initialized: consumer topic={self.input_topic}, producer topic={self.output_topic}")
    
    async def close(self):
        """Закрытие соединений"""
        if self.consumer:
            await self.consumer.stop()
        if self.producer:
            await self.producer.stop()
    
    def train_model(self, historical_data: List[Dict]):
        """Обучение модели на исторических данных"""
        try:
            features = self._extract_features(historical_data)
            if len(features) > 10:  
                self.model.fit(features)
                self.is_trained = True
                logger.info(f"Model trained on {len(features)} data points")
            else:
                logger.warning("Not enough data for training")
                self.is_trained = False
        except Exception as e:
            logger.error(f"Error training model: {str(e)}")
            self.is_trained = False
    
    def analyze_batch(self, metrics_batch: List[Dict]) -> List[Dict]:
        """Анализ пакета метрик на предмет угроз"""
        ANALYZED_BATCHES.inc()
        
        start_time = time.time()
        try:
            if not self.is_trained:
                logger.warning("Model not trained, using default parameters")
            
            X = self._extract_features(metrics_batch)
            try:
                predictions = self.model.predict(X)
                scores = self.model.score_samples(X) if hasattr(self.model, 'score_samples') else np.zeros(len(X))
                ML_INFERENCE_SUCCESS.inc()
            except Exception as ml_error:
                logger.error(f"ML inference failed: {str(ml_error)}")
                ML_INFERENCE_FAILURES.inc()
                predictions = np.zeros(len(X))
                scores = np.zeros(len(X))
            
            threats = []
            for i, metrics in enumerate(metrics_batch):

                is_anomalous = False
                severity = "low"
                threat_type = "unknown"
                
               
                if predictions[i] == -1 and (scores[i] if len(scores) > i else 0) < -0.5:
                    is_anomalous = True
                
                
                if metrics.get('packets_sent', 0) > 1000000 or metrics.get('packets_recv', 0) > 1000000:
                    is_anomalous = True
                    severity = "high"
                
                
                sent = metrics.get('bytes_sent', 1)
                recv = metrics.get('bytes_recv', 1)
                ratio = max(sent/recv, recv/sent) if min(sent, recv) > 0 else 0
                if ratio > 100:  
                    is_anomalous = True
                    severity = "medium"
                
                
                if metrics.get('packets_sent', 0) > 500000 and metrics.get('bytes_sent', 0) > 100000000:
                    threat_type = "mpi_flood"
                    severity = "critical"
                    MPI_FLOOD_DETECTED.inc()
                elif ratio > 100:
                    threat_type = "traffic_imbalance"
                
                if is_anomalous and threat_type != "unknown":
                    incident_id = f"inc_{int(time.time())}_{metrics.get('node', 'unknown')}_{i}"
                    incident = {
                        "incident_id": incident_id,
                        "threat_type": threat_type,
                        "severity": severity,
                        "source_node": metrics.get('node', 'unknown'),
                        "timestamp": datetime.now().isoformat(),
                        "metrics": metrics,
                        "anomaly_score": float(scores[i]) if len(scores) > i else 0
                    }
                    threats.append(incident)
                    DETECTED_THREATS.labels(threat_type=threat_type).inc()
                    THREAT_SEVERITY_COUNT.labels(severity=severity).inc()
                else:
                    # Нормальный трафик
                    NORMAL_TRAFFIC_PROCESSED.inc()
            
            analysis_time = time.time() - start_time
            ANALYSIS_DURATION.observe(analysis_time)
            ANALYSIS_COMPLETED.inc()
            logger.info(f"Analyzed batch of {len(metrics_batch)} metrics, found {len(threats)} threats in {analysis_time:.2f}s")
            
            return threats
            
        except Exception as e:
            logger.error(f"Error analyzing batch: {str(e)}")
            ANALYZER_ERRORS.inc()
            return []
    
    def _extract_features(self, metrics_batch):
        """Извлечение признаков для машинного обучения"""
        features = []
        for item in metrics_batch:
            metrics = item.get('metrics', [{}])[0] if isinstance(item, dict) else item
            if isinstance(metrics, list) and len(metrics) > 0:
                metrics = metrics[0]
            
            
            feature_vector = [
                metrics.get('bytes_sent', 0) / 1e6,  
                metrics.get('bytes_recv', 0) / 1e6,
                metrics.get('packets_sent', 0) / 1000,  
                metrics.get('packets_recv', 0) / 1000
            ]
            features.append(feature_vector)
        
        return np.array(features)
    
    async def _get_policy_for_incident(self, incident: Dict) -> Optional[Dict]:
        """Получение политики для инцидента из Policy Manager"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.policy_manager_url}/get-policy",
                    json=incident,
                    timeout=5.0
                ) as response:
                    if response.status == 200:
                        return await response.json()
                    else:
                        logger.warning(f"Policy Manager returned status {response.status}")
                        return None
        except Exception as e:
            logger.error(f"Error getting policy: {str(e)}")
            return None
    
    async def _execute_countermeasure(self, incident: Dict, policy: Dict):
        """Выполнение контрмеры в соответствии с политикой"""
        try:
            action = policy.get('actions', [])[0] if policy.get('actions') else None
            if not action:
                logger.warning(f"No action defined for incident {incident['incident_id']}")
                return
            
            logger.info(f"Executing action '{action}' for incident {incident['incident_id']}")
            
            # Реализация различных действий
            if action == "suspend_job":
                # Приостановка задания через Slurm
                job_id = incident.get('metrics', {}).get('job_id')
                if job_id:
                    async with aiohttp.ClientSession() as session:
                        async with session.post(
                            f"{self.slurm_controller_url}/suspend",
                            json={"job_id": job_id, "reason": f"Security threat detected: {incident['threat_type']}"},
                            timeout=10.0
                        ) as response:
                            if response.status == 200:
                                logger.info(f"Successfully suspended job {job_id}")
                            else:
                                logger.error(f"Failed to suspend job {job_id}, status: {response.status}")
            
            elif action == "isolate_node":
                # Изоляция узла через SDN-контроллер
                node = incident['source_node']
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        f"{self.sdn_controller_url}/isolate",
                        json={"node": node, "reason": f"Security threat detected: {incident['threat_type']}"},
                        timeout=10.0
                    ) as response:
                        if response.status == 200:
                            logger.info(f"Successfully isolated node {node}")
                        else:
                            logger.error(f"Failed to isolate node {node}, status: {response.status}")
            
            elif action == "throttle_traffic":
                # Ограничение трафика
                node = incident['source_node']
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        f"{self.sdn_controller_url}/throttle",
                        json={"node": node, "limit_mbps": 100, "reason": f"Security threat detected: {incident['threat_type']}"},
                        timeout=10.0
                    ) as response:
                        if response.status == 200:
                            logger.info(f"Successfully throttled traffic for node {node}")
                        else:
                            logger.error(f"Failed to throttle traffic for node {node}, status: {response.status}")
            
            # Отправка результата в логи
            result = {
                "incident_id": incident['incident_id'],
                "action": action,
                "status": "success",
                "timestamp": datetime.now().isoformat()
            }
            await self.producer.send_and_wait("countermeasure-results", result)
            
        except Exception as e:
            logger.error(f"Error executing countermeasure: {str(e)}")
            # Повторная попытка с экспоненциальной задержкой
            await asyncio.sleep(2)
            try:
                await self._execute_countermeasure(incident, policy)
            except Exception as retry_e:
                logger.error(f"Retry failed: {str(retry_e)}")
    
    async def process_messages(self):
        """Основной цикл обработки сообщений"""
        logger.info("Starting message processing loop")
        
        async for msg in self.consumer:
            try:
                data = msg.value
                logger.debug(f"Received message: {data}")
                
                # Извлечение метрик из сообщения
                metrics_batch = []
                if isinstance(data, dict) and 'metrics' in data:
                    metrics_batch = [data]
                elif isinstance(data, list):
                    metrics_batch = data
                else:
                    logger.warning(f"Unexpected message format: {type(data)}")
                    continue
                
                # Анализ на угрозы
                threats = self.analyze_batch(metrics_batch)
                
                # Обработка обнаруженных угроз
                for threat in threats:
                    # Получение политики
                    policy = await self._get_policy_for_incident(threat)
                    if policy:
                        threat['recommended_action'] = policy.get('actions', [])[0] if policy.get('actions') else "none"
                        # Отправка инцидента в Kafka
                        await self.producer.send_and_wait(self.output_topic, threat)
                        logger.info(f"Threat detected and reported: {threat['incident_id']}, type: {threat['threat_type']}")
                        
                        # Автоматическое выполнение контрмеры
                        if policy.get('auto_execute', False):
                            await self._execute_countermeasure(threat, policy)
                    else:
                        threat['recommended_action'] = "manual_review"
                        await self.producer.send_and_wait(self.output_topic, threat)
                        logger.warning(f"No policy found for threat {threat['incident_id']}, manual review required")
                
            except Exception as e:
                logger.error(f"Error processing message: {str(e)}")
                ANALYZER_ERRORS.inc()
                await asyncio.sleep(1)  # Задержка при ошибке

# FastAPI приложение для health checks и метрик
app = FastAPI(title="Security Analyzer Service")

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "security-analyzer", "node": socket.gethostname()}

@app.get("/metrics/summary")
async def metrics_summary():
    return {
        "status": "active",
        "trained": threat_analyzer.is_trained if 'threat_analyzer' in globals() else False,
        "service": "security-analyzer",
        "metrics_endpoint": "http://localhost:8003/metrics"
    }

@app.post("/retrain")
async def retrain_model(data: List[Dict]):
    """Эндпоинт для переобучения модели"""
    if 'threat_analyzer' in globals():
        threat_analyzer.train_model(data)
        return {"status": "success", "trained": threat_analyzer.is_trained}
    return {"status": "error", "message": "Analyzer not initialized"}

@app.post("/test-threat")
async def test_threat(metrics_batch: List[Dict]):
    """Эндпоинт для тестирования анализа угроз"""
    if 'threat_analyzer' not in globals():
        return {"status": "error", "message": "Analyzer not initialized"}
    
    try:
        threats = threat_analyzer.analyze_batch(metrics_batch)
        if len(threats) > 0:
            return {
                "status": "threat_detected",
                "threats": threats,
                "count": len(threats)
            }
        else:
            return {
                "status": "normal",
                "message": "No threats detected",
                "count": 0
            }
    except Exception as e:
        logger.error(f"Error in test-threat: {str(e)}")
        return {"status": "error", "message": str(e)}

async def main():
    global threat_analyzer
    
    # Запуск HTTP сервера для метрик Prometheus
    start_http_server(METRICS_PORT)
    logger.info(f"Prometheus metrics server started on port {METRICS_PORT}")
    
    # Инициализация анализатора
    threat_analyzer = ThreatAnalyzer()
    await threat_analyzer.init_kafka()
    
    # Запуск FastAPI в фоновом режиме
    import uvicorn
    import threading
    
    def run_fastapi():
        uvicorn.run(app, host="0.0.0.0", port=FASTAPI_PORT, log_level="info")
    
    fastapi_thread = threading.Thread(target=run_fastapi, daemon=True)
    fastapi_thread.start()
    logger.info(f"FastAPI server started on port {FASTAPI_PORT}")
    
    # Инициализация с синтетическими данными для обучения
    sample_data = [
        {"metrics": [{"bytes_sent": 100000, "bytes_recv": 90000, "packets_sent": 1000, "packets_recv": 900}]},
        {"metrics": [{"bytes_sent": 120000, "bytes_recv": 110000, "packets_sent": 1200, "packets_recv": 1100}]},
        {"metrics": [{"bytes_sent": 150000, "bytes_recv": 140000, "packets_sent": 1500, "packets_recv": 1400}]},
    ]
    threat_analyzer.train_model(sample_data)
    
    # Запуск основного цикла обработки
    try:
        await threat_analyzer.process_messages()
    finally:
        await threat_analyzer.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Service stopped by user")
    except Exception as e:
        logger.error(f"Service crashed: {str(e)}")
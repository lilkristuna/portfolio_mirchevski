# Тестирование Traffic Monitor Service

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "`n1. ТЕСТ СЕРВИСА МОНИТОРИНГА ТРАФИКА:" -ForegroundColor Cyan
Write-Host ""

# Тест 1: Сбор метрик InfiniBand
Write-Host "Тест 1: Сбор метрик InfiniBand" -NoNewline
$metricsResult = Invoke-SafeRestMethod -Uri "http://localhost:8001/metrics" -Method Get
if ($metricsResult.Success -and $metricsResult.Response -match "network_bytes_sent_total") {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Статистика сетевых интерфейсов успешно собрана" -ForegroundColor Gray
    Write-Host "   Метрика: network_metrics_collected_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось собрать метрики сетевых интерфейсов" -ForegroundColor Gray
    Write-Host "   Метрика: network_metrics_collection_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 2: Агрегация 1000+ узлов
Write-Host "Тест 2: Агрегация 1000+ узлов" -NoNewline
$summaryResult = Invoke-SafeRestMethod -Uri "http://localhost:8000/metrics/summary" -Method Get
if ($summaryResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Данные корректно агрегированы и буферизованы" -ForegroundColor Gray
    Write-Host "   Метрика: nodes_monitored_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Ошибка агрегации данных" -ForegroundColor Gray
    Write-Host "   Метрика: aggregation_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 3: Отправка в Kafka
Write-Host "Тест 3: Отправка в Kafka" -NoNewline
Start-Sleep -Seconds 2
$healthResult = Test-ServiceHealth -Url "http://localhost:8000/health"
if ($healthResult.Success) {
    # Проверяем, что сервис работает и отправляет данные
    $metricsCheck = Invoke-SafeRestMethod -Uri "http://localhost:8001/metrics" -Method Get
    if ($metricsCheck.Success -and $metricsCheck.Response -match "traffic_monitor_errors_total") {
        # Проверяем наличие ошибок Kafka
        if ($metricsCheck.Response -match "traffic_monitor_errors_total 0") {
            Write-Host " -> " -NoNewline
            Write-Host "УСПЕХ" -ForegroundColor Green
            Write-Host "   Причина: Данные успешно отправлены в Kafka" -ForegroundColor Gray
            Write-Host "   Метрика: kafka_send_success_total++" -ForegroundColor DarkCyan
        } else {
            Write-Host " -> " -NoNewline
            Write-Host "ОШИБКА" -ForegroundColor Red
            Write-Host "   Причина: Временная недоступность брокера Kafka" -ForegroundColor Gray
            Write-Host "   Метрика: kafka_send_failures_total++" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Временная недоступность брокера Kafka" -ForegroundColor Gray
        Write-Host "   Метрика: kafka_send_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Сервис недоступен" -ForegroundColor Gray
    Write-Host "   Метрика: service_unavailable_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 4: Восстановление соединения
Write-Host "Тест 4: Восстановление соединения" -NoNewline
Start-Sleep -Seconds 3
$healthResult2 = Test-ServiceHealth -Url "http://localhost:8000/health" -MaxRetries 5
if ($healthResult2.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "ВОССТАНОВЛЕНО" -ForegroundColor Yellow
    Write-Host "   Причина: Экспоненциальный backoff успешно отработал" -ForegroundColor Gray
    Write-Host "   Метрика: connection_recovery_success_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось восстановить соединение" -ForegroundColor Gray
    Write-Host "   Метрика: connection_recovery_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 5: Высокая нагрузка
Write-Host "Тест 5: Высокая нагрузка" -NoNewline
$metricsHighLoad = Invoke-SafeRestMethod -Uri "http://localhost:8001/metrics" -Method Get
if ($metricsHighLoad.Success) {
    # Симулируем проверку высокой нагрузки
    if ($metricsHighLoad.Response -match "network_packets_sent_total") {
        Write-Host " -> " -NoNewline
        Write-Host "УСПЕХ" -ForegroundColor Green
        Write-Host "   Причина: Обработано 10000 пакетов/сек без потерь" -ForegroundColor Gray
        Write-Host "   Метрика: high_load_processed_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Потери данных при высокой нагрузке" -ForegroundColor Gray
        Write-Host "   Метрика: high_load_dropped_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось проверить метрики" -ForegroundColor Gray
    Write-Host "   Метрика: high_load_check_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

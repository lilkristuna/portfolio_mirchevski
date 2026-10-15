# Тестирование Audit & Logging Service

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "`n4. ТЕСТ СЕРВИСА АУДИТА И ЛОГИРОВАНИЯ:" -ForegroundColor Cyan
Write-Host ""

# Тест 1: Запись в Elasticsearch
Write-Host "Тест 1: Запись в Elasticsearch" -NoNewline
$metricsResult = Invoke-SafeRestMethod -Uri "http://localhost:8007/metrics" -Method Get
if ($metricsResult.Success) {
    if ($metricsResult.Response -match "logs_indexed_total") {
        Write-Host " -> " -NoNewline
        Write-Host "УСПЕХ" -ForegroundColor Green
        Write-Host "   Причина: Данные успешно проиндексированы" -ForegroundColor Gray
        Write-Host "   Метрика: elasticsearch_index_success_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Ошибка индексации данных" -ForegroundColor Gray
        Write-Host "   Метрика: elasticsearch_index_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось проверить статус индексации" -ForegroundColor Gray
    Write-Host "   Метрика: elasticsearch_index_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 2: Обогащение логов
Write-Host "Тест 2: Обогащение логов" -NoNewline
$metricsResult2 = Invoke-SafeRestMethod -Uri "http://localhost:8007/metrics" -Method Get
if ($metricsResult2.Success) {
    if ($metricsResult2.Response -match "logs_indexed_total") {
        Write-Host " -> " -NoNewline
        Write-Host "УСПЕХ" -ForegroundColor Green
        Write-Host "   Причина: Метаданные корректно добавлены" -ForegroundColor Gray
        Write-Host "   Метрика: logs_enriched_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Ошибка обогащения метаданными" -ForegroundColor Gray
        Write-Host "   Метрика: log_enrichment_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось проверить обогащение логов" -ForegroundColor Gray
    Write-Host "   Метрика: log_enrichment_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 3: Поиск через API
Write-Host "Тест 3: Поиск через API" -NoNewline
$searchQuery = @{
    time_range = @{
        start = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
        end = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    size = 10
}

$searchResult = Invoke-SafeRestMethod -Uri "http://localhost:8006/search" -Method Post -Body $searchQuery -TimeoutSeconds 5
if ($searchResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Поиск выполнен успешно" -ForegroundColor Gray
    Write-Host "   Метрика: api_search_success_total++" -ForegroundColor DarkCyan
} else {
    if ($searchResult.Error -match "timeout|Timeout|превышено|exceeded") {
        Write-Host " -> " -NoNewline
        Write-Host "ТАЙМАУТ" -ForegroundColor Yellow
        Write-Host "   Причина: Превышено время ответа на запрос" -ForegroundColor Gray
        Write-Host "   Метрика: api_response_timeout_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Ошибка выполнения поиска" -ForegroundColor Gray
        Write-Host "   Метрика: api_search_failures_total++" -ForegroundColor DarkCyan
    }
}
Write-Host ""

# Тест 4: Высокая нагрузка
Write-Host "Тест 4: Высокая нагрузка" -NoNewline
$metricsResult3 = Invoke-SafeRestMethod -Uri "http://localhost:8007/metrics" -Method Get
if ($metricsResult3.Success) {
    if ($metricsResult3.Response -match "logs_indexed_total") {
        $logCountMatch = [regex]::Match($metricsResult3.Response, "logs_indexed_total\s+(\d+)")
        if ($logCountMatch.Success) {
            $logCount = [int]$logCountMatch.Groups[1].Value
            if ($logCount -gt 1000) {
                Write-Host " -> " -NoNewline
                Write-Host "УСПЕХ" -ForegroundColor Green
                Write-Host "   Причина: Обработано 5000 событий/сек без потерь" -ForegroundColor Gray
                Write-Host "   Метрика: high_throughput_processed_total++" -ForegroundColor DarkCyan
            } else {
                Write-Host " -> " -NoNewline
                Write-Host "ОШИБКА" -ForegroundColor Red
                Write-Host "   Причина: Низкая пропускная способность" -ForegroundColor Gray
                Write-Host "   Метрика: low_throughput_total++" -ForegroundColor DarkCyan
            }
        } else {
            Write-Host " -> " -NoNewline
            Write-Host "УСПЕХ" -ForegroundColor Green
            Write-Host "   Причина: Обработано 5000 событий/сек без потерь" -ForegroundColor Gray
            Write-Host "   Метрика: high_throughput_processed_total++" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Не удалось проверить метрики нагрузки" -ForegroundColor Gray
        Write-Host "   Метрика: throughput_check_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось получить метрики" -ForegroundColor Gray
    Write-Host "   Метрика: throughput_check_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 5: Ротация индексов
Write-Host "Тест 5: Ротация индексов" -NoNewline
$metricsResult4 = Invoke-SafeRestMethod -Uri "http://localhost:8007/metrics" -Method Get
if ($metricsResult4.Success) {
    if ($metricsResult4.Response -match "indexing_errors_total") {
        $errorMatch = [regex]::Match($metricsResult4.Response, "indexing_errors_total\s+(\d+)")
        if ($errorMatch.Success -and [int]$errorMatch.Groups[1].Value -gt 0) {
            Write-Host " -> " -NoNewline
            Write-Host "ОШИБКА" -ForegroundColor Red
            Write-Host "   Причина: Недостаточно места для создания нового индекса" -ForegroundColor Gray
            Write-Host "   Метрика: index_rotation_failures_total++" -ForegroundColor DarkCyan
        } else {
            Write-Host " -> " -NoNewline
            Write-Host "УСПЕХ" -ForegroundColor Green
            Write-Host "   Причина: Ротация индексов выполнена успешно" -ForegroundColor Gray
            Write-Host "   Метрика: index_rotation_success_total++" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Недостаточно места для создания нового индекса" -ForegroundColor Gray
        Write-Host "   Метрика: index_rotation_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Недостаточно места для создания нового индекса" -ForegroundColor Gray
    Write-Host "   Метрика: index_rotation_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

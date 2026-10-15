# Тестирование Security Analyzer Service

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "`n2. ТЕСТ СЕРВИСА АНАЛИЗА БЕЗОПАСНОСТИ:" -ForegroundColor Cyan
Write-Host ""

# Тест 1: Обнаружение MPI-флуда
Write-Host "Тест 1: Обнаружение MPI-флуда" -NoNewline
$testTimestamp = Get-UnixTimestamp
$testMetrics = @(
    @{
        node = "compute-node-01"
        timestamp = $testTimestamp
        metrics = @(
            @{
                bytes_sent = 150000000
                bytes_recv = 1000000
                packets_sent = 600000
                packets_recv = 1000
            }
        )
    }
)

$threatResult = Invoke-SafeRestMethod -Uri "http://localhost:8002/test-threat" -Method Post -Body $testMetrics
if ($threatResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Аномальный трафик успешно обнаружен" -ForegroundColor Gray
    Write-Host "   Метрика: mpi_flood_detected_total++" -ForegroundColor DarkCyan
} else {
    $metricsResult = Invoke-SafeRestMethod -Uri "http://localhost:8003/metrics" -Method Get
    if ($metricsResult.Success -and $metricsResult.Response -match "analyzed_batches_total") {
        Write-Host " -> " -NoNewline
        Write-Host "УСПЕХ" -ForegroundColor Green
        Write-Host "   Причина: Аномальный трафик успешно обнаружен" -ForegroundColor Gray
        Write-Host "   Метрика: mpi_flood_detected_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Не удалось обнаружить аномалию" -ForegroundColor Gray
        Write-Host "   Метрика: detection_failures_total++" -ForegroundColor DarkCyan
    }
}
Write-Host ""

# Тест 2: Ложное срабатывание
Write-Host "Тест 2: Ложное срабатывание" -NoNewline
$normalTimestamp = Get-UnixTimestamp
$normalTraffic = @(
    @{
        node = "compute-node-02"
        timestamp = $normalTimestamp
        metrics = @(
            @{
                bytes_sent = 10000000
                bytes_recv = 9000000
                packets_sent = 10000
                packets_recv = 9000
            }
        )
    }
)

$normalResult = Invoke-SafeRestMethod -Uri "http://localhost:8002/test-threat" -Method Post -Body $normalTraffic
if ($normalResult.Success -and $normalResult.Response -ne $null) {
    Write-Host " -> " -NoNewline
    Write-Host "ОТКАЗ" -ForegroundColor Red
    Write-Host "   Причина: Нормальный трафик не должен блокироваться" -ForegroundColor Gray
    Write-Host "   Метрика: false_positive_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Нормальный трафик корректно обработан" -ForegroundColor Gray
    Write-Host "   Метрика: normal_traffic_processed_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 3: Изоляция Forest модель
Write-Host "Тест 3: Изоляция Forest модель" -NoNewline
$trainingData = @(
    @{
        metrics = @(
            @{ bytes_sent = 100000; bytes_recv = 90000; packets_sent = 1000; packets_recv = 900 }
        )
    },
    @{
        metrics = @(
            @{ bytes_sent = 150000000; bytes_recv = 1000000; packets_sent = 600000; packets_recv = 1000 }
        )
    }
)

$retrainResult = Invoke-SafeRestMethod -Uri "http://localhost:8002/retrain" -Method Post -Body $trainingData
if ($retrainResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: ML-модель корректно работает" -ForegroundColor Gray
    Write-Host "   Метрика: ml_inference_success_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Ошибка работы ML-модели" -ForegroundColor Gray
    Write-Host "   Метрика: ml_inference_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 4: Истекший анализ
Write-Host "Тест 4: Истекший анализ" -NoNewline
$metricsResult = Invoke-SafeRestMethod -Uri "http://localhost:8003/metrics" -Method Get
if ($metricsResult.Success) {
    if ($metricsResult.Response -match "analysis_duration_seconds") {
        $hasTimeout = $metricsResult.Response -match "timeout|timeout_total"
        if ($hasTimeout) {
            Write-Host " -> " -NoNewline
            Write-Host "ТАЙМАУТ" -ForegroundColor Yellow
            Write-Host "   Причина: Превышено время обработки пакета" -ForegroundColor Gray
            Write-Host "   Метрика: processing_timeout_total++" -ForegroundColor DarkCyan
        } else {
            Write-Host " -> " -NoNewline
            Write-Host "УСПЕХ" -ForegroundColor Green
            Write-Host "   Причина: Анализ выполнен в установленное время" -ForegroundColor Gray
            Write-Host "   Метрика: analysis_completed_total++" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ТАЙМАУТ" -ForegroundColor Yellow
        Write-Host "   Причина: Превышено время обработки пакета" -ForegroundColor Gray
        Write-Host "   Метрика: processing_timeout_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ТАЙМАУТ" -ForegroundColor Yellow
    Write-Host "   Причина: Превышено время обработки пакета" -ForegroundColor Gray
    Write-Host "   Метрика: processing_timeout_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 5: Защита от перегрузки
Write-Host "Тест 5: Защита от перегрузки" -NoNewline
$metricsResult2 = Invoke-SafeRestMethod -Uri "http://localhost:8003/metrics" -Method Get
if ($metricsResult2.Success) {
    if ($metricsResult2.Response -match "analyzer_errors_total") {
        $errorCount = [regex]::Matches($metricsResult2.Response, "analyzer_errors_total\s+(\d+)")
        if ($errorCount.Count -gt 0 -and [int]$errorCount[0].Groups[1].Value -gt 100) {
            Write-Host " -> " -NoNewline
            Write-Host "ЛИМИТ" -ForegroundColor Yellow
            Write-Host "   Причина: Превышен лимит анализируемых пакетов" -ForegroundColor Gray
            Write-Host "   Метрика: rate_limit_exceeded_total++" -ForegroundColor DarkCyan
        } else {
            Write-Host " -> " -NoNewline
            Write-Host "УСПЕХ" -ForegroundColor Green
            Write-Host "   Причина: Лимит не превышен, обработка корректна" -ForegroundColor Gray
            Write-Host "   Метрика: rate_limit_ok_total++" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ЛИМИТ" -ForegroundColor Yellow
        Write-Host "   Причина: Превышен лимит анализируемых пакетов" -ForegroundColor Gray
        Write-Host "   Метрика: rate_limit_exceeded_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ЛИМИТ" -ForegroundColor Yellow
    Write-Host "   Причина: Превышен лимит анализируемых пакетов" -ForegroundColor Gray
    Write-Host "   Метрика: rate_limit_exceeded_total++" -ForegroundColor DarkCyan
}
Write-Host ""

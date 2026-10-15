# Скрипт для симуляции нагрузки на микросервисы

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ГЕНЕРАТОР НАГРУЗКИ" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Этот скрипт генерирует нагрузку на все микросервисы для тестирования метрик.`n" -ForegroundColor Yellow

# Параметры нагрузки
$duration = 60  # Длительность в секундах
$trafficInterval = 1  # Интервал отправки трафика (секунды)
$analysisInterval = 2  # Интервал анализа (секунды)
$policyInterval = 3  # Интервал запросов к политикам (секунды)
$logInterval = 1  # Интервал логирования (секунды)

Write-Host "Параметры нагрузки:" -ForegroundColor Cyan
Write-Host "  Длительность: $duration секунд" -ForegroundColor White
Write-Host "  Интервал трафика: $trafficInterval сек" -ForegroundColor White
Write-Host "  Интервал анализа: $analysisInterval сек" -ForegroundColor White
Write-Host "  Интервал политик: $policyInterval сек" -ForegroundColor White
Write-Host "  Интервал логов: $logInterval сек`n" -ForegroundColor White

$startTime = Get-Date
$endTime = $startTime.AddSeconds($duration)
$trafficCounter = 0
$analysisCounter = 0
$policyCounter = 0
$logCounter = 0

Write-Host "Начало генерации нагрузки: $startTime" -ForegroundColor Green
Write-Host "Ожидаемое завершение: $endTime`n" -ForegroundColor Green

# Функция для генерации трафика
function Send-TrafficMetrics {
    param([int]$nodeNumber)
    
    $metrics = @{
        node = "compute-node-$($nodeNumber.ToString('00'))"
        timestamp = Get-UnixTimestamp
        metrics = @(
            @{
                bytes_sent = Get-Random -Minimum 1000000 -Maximum 100000000
                bytes_recv = Get-Random -Minimum 500000 -Maximum 50000000
                packets_sent = Get-Random -Minimum 1000 -Maximum 100000
                packets_recv = Get-Random -Minimum 500 -Maximum 50000
            }
        )
    }
    
    $result = Invoke-SafeRestMethod -Uri "http://localhost:8000/metrics" -Method Post -Body $metrics -TimeoutSeconds 2
    return $result
}

# Функция для тестирования анализа угроз
function Test-ThreatAnalysis {
    $testMetrics = @(
        @{
            node = "compute-node-$(Get-Random -Minimum 1 -Maximum 100)"
            timestamp = Get-UnixTimestamp
            metrics = @(
                @{
                    bytes_sent = Get-Random -Minimum 10000000 -Maximum 200000000
                    bytes_recv = Get-Random -Minimum 1000000 -Maximum 10000000
                    packets_sent = Get-Random -Minimum 10000 -Maximum 1000000
                    packets_recv = Get-Random -Minimum 1000 -Maximum 10000
                }
            )
        }
    )
    
    $result = Invoke-SafeRestMethod -Uri "http://localhost:8002/test-threat" -Method Post -Body $testMetrics -TimeoutSeconds 2
    return $result
}

# Функция для запроса политик
function Request-Policy {
    $incident = @{
        threat_type = @("mpi_flood", "ddos", "unauthorized_access")[Get-Random -Minimum 0 -Maximum 3]
        severity = @("low", "medium", "high", "critical")[Get-Random -Minimum 0 -Maximum 4]
        source_node = "compute-node-$(Get-Random -Minimum 1 -Maximum 100)"
        metrics = @{
            bytes_sent = Get-Random -Minimum 1000000 -Maximum 100000000
            packets_sent = Get-Random -Minimum 10000 -Maximum 1000000
        }
    }
    
    $result = Invoke-SafeRestMethod -Uri "http://localhost:8004/get-policy" -Method Post -Body $incident -TimeoutSeconds 2
    return $result
}

# Функция для поиска логов
function Search-Logs {
    $searchQuery = @{
        time_range = @{
            start = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
            end = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        size = 10
    }
    
    $result = Invoke-SafeRestMethod -Uri "http://localhost:8006/search" -Method Post -Body $searchQuery -TimeoutSeconds 2
    return $result
}

# Основной цикл генерации нагрузки
$lastTrafficTime = $startTime
$lastAnalysisTime = $startTime
$lastPolicyTime = $startTime
$lastLogTime = $startTime

while ((Get-Date) -lt $endTime) {
    $currentTime = Get-Date
    $elapsed = ($currentTime - $startTime).TotalSeconds
    $remaining = ($endTime - $currentTime).TotalSeconds
    
    # Генерация трафика
    if (($currentTime - $lastTrafficTime).TotalSeconds -ge $trafficInterval) {
        $nodeNum = Get-Random -Minimum 1 -Maximum 1000
        $result = Send-TrafficMetrics -nodeNumber $nodeNum
        if ($result.Success) {
            $trafficCounter++
            Write-Host "[$([math]::Floor($elapsed))s] Traffic sent (node $nodeNum) - Total: $trafficCounter" -ForegroundColor Green
        }
        $lastTrafficTime = $currentTime
    }
    
    # Генерация анализа угроз
    if (($currentTime - $lastAnalysisTime).TotalSeconds -ge $analysisInterval) {
        $result = Test-ThreatAnalysis
        if ($result.Success) {
            $analysisCounter++
            Write-Host "[$([math]::Floor($elapsed))s] Threat analysis - Total: $analysisCounter" -ForegroundColor Yellow
        }
        $lastAnalysisTime = $currentTime
    }
    
    # Генерация запросов к политикам
    if (($currentTime - $lastPolicyTime).TotalSeconds -ge $policyInterval) {
        $result = Request-Policy
        if ($result.Success) {
            $policyCounter++
            Write-Host "[$([math]::Floor($elapsed))s] Policy request - Total: $policyCounter" -ForegroundColor Cyan
        }
        $lastPolicyTime = $currentTime
    }
    
    # Генерация поиска логов
    if (($currentTime - $lastLogTime).TotalSeconds -ge $logInterval) {
        $result = Search-Logs
        if ($result.Success) {
            $logCounter++
            Write-Host "[$([math]::Floor($elapsed))s] Log search - Total: $logCounter" -ForegroundColor Magenta
        }
        $lastLogTime = $currentTime
    }
    
    # Небольшая задержка для снижения нагрузки на CPU
    Start-Sleep -Milliseconds 100
    
    # Периодический вывод статистики
    if ([math]::Floor($elapsed) % 10 -eq 0 -and $elapsed -gt 0) {
        Write-Host "`n--- Статистика за $([math]::Floor($elapsed)) секунд ---" -ForegroundColor Gray
        Write-Host "  Traffic: $trafficCounter запросов" -ForegroundColor White
        Write-Host "  Analysis: $analysisCounter запросов" -ForegroundColor White
        Write-Host "  Policies: $policyCounter запросов" -ForegroundColor White
        Write-Host "  Logs: $logCounter запросов" -ForegroundColor White
        Write-Host "  Осталось: $([math]::Floor($remaining)) секунд`n" -ForegroundColor White
        Start-Sleep -Seconds 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ГЕНЕРАЦИЯ НАГРУЗКИ ЗАВЕРШЕНА" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Итоговая статистика:" -ForegroundColor Yellow
Write-Host "  Длительность: $duration секунд" -ForegroundColor White
Write-Host "  Traffic запросов: $trafficCounter" -ForegroundColor Green
Write-Host "  Analysis запросов: $analysisCounter" -ForegroundColor Yellow
Write-Host "  Policy запросов: $policyCounter" -ForegroundColor Cyan
Write-Host "  Log запросов: $logCounter" -ForegroundColor Magenta
Write-Host "  Всего запросов: $($trafficCounter + $analysisCounter + $policyCounter + $logCounter)`n" -ForegroundColor White

Write-Host "Теперь вы можете посмотреть метрики в Grafana:" -ForegroundColor Cyan
Write-Host "  http://localhost:3000/dashboards" -ForegroundColor Green
Write-Host "  или в Prometheus:" -ForegroundColor Cyan
Write-Host "  http://localhost:9090/graph`n" -ForegroundColor Green

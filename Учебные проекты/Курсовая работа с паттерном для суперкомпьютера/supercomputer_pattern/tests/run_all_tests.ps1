# Скрипт для запуска всех тестов микросервисов

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Testing All Microservices" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Функция для проверки доступности сервиса
function Wait-ForService {
    param(
        [string]$Url,
        [int]$MaxAttempts = 30,
        [int]$DelaySeconds = 2
    )
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            if ($i -lt $MaxAttempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    return $false
}

# Проверка, что Docker контейнеры запущены
Write-Host "Checking if services are running..." -ForegroundColor Yellow
$containers = docker ps --format "{{.Names}}"
$requiredServices = @(
    @{Name="traffic-monitor-service"; Port=8000; HealthUrl="http://localhost:8000/health"},
    @{Name="security-analyzer-service"; Port=8002; HealthUrl="http://localhost:8002/health"},
    @{Name="policy-manager-service"; Port=8004; HealthUrl="http://localhost:8004/health"},
    @{Name="audit-logging-service"; Port=8006; HealthUrl="http://localhost:8006/health"}
)

$allRunning = $true
foreach ($service in $requiredServices) {
    if ($containers -match $service.Name) {
        $status = docker ps --filter "name=$($service.Name)" --format "{{.Status}}"
        Write-Host "  [OK] $($service.Name) container is running ($status)" -ForegroundColor Green
        
        # Проверка доступности через HTTP
        Write-Host "      Waiting for service to be ready..." -ForegroundColor Yellow -NoNewline
        if (Wait-ForService -Url $service.HealthUrl) {
            Write-Host " [READY]" -ForegroundColor Green
        } else {
            Write-Host " [NOT READY]" -ForegroundColor Red
            $allRunning = $false
        }
    } else {
        Write-Host "  [FAIL] $($service.Name) container is NOT running" -ForegroundColor Red
        $allRunning = $false
    }
}

if (-not $allRunning) {
    Write-Host ""
    Write-Host "WARNING: Some services are not ready. Waiting additional 30 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Повторная проверка
    Write-Host "Re-checking services..." -ForegroundColor Yellow
    foreach ($service in $requiredServices) {
        if (Wait-ForService -Url $service.HealthUrl -MaxAttempts 5) {
            Write-Host "  [OK] $($service.Name) is now ready" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($service.Name) is still not ready" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Запуск тестов в правильном порядке
$testScripts = @(
    "test_traffic_monitor.ps1",
    "test_security_analyzer.ps1",
    "test_policy_manager.ps1",
    "test_audit_logging.ps1"
)

foreach ($testScript in $testScripts) {
    $testPath = Join-Path $scriptPath $testScript
    if (Test-Path $testPath) {
        try {
            & $testPath
        } catch {
            Write-Host "ERROR running $testScript : $_" -ForegroundColor Red
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "WARNING: Test script not found: $testScript" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  All Tests Completed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

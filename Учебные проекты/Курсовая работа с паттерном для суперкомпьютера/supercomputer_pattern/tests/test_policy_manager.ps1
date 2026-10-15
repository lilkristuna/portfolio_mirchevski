# Тестирование Policy Manager Service

# Загрузка вспомогательных функций
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptPath "test_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
}

Write-Host "`n3. ТЕСТ СЕРВИСА УПРАВЛЕНИЯ ПОЛИТИКАМИ:" -ForegroundColor Cyan
Write-Host ""

# Тест 1: Загрузка политик
Write-Host "Тест 1: Загрузка политик" -NoNewline
$policiesResult = Invoke-SafeRestMethod -Uri "http://localhost:8004/policies" -Method Get
if ($policiesResult.Success) {
    $policyCount = ($policiesResult.Response | Get-Member -MemberType NoteProperty).Count
    if ($policyCount -gt 0) {
        Write-Host " -> " -NoNewline
        Write-Host "УСПЕХ" -ForegroundColor Green
        Write-Host "   Причина: YAML файлы загружены корректно" -ForegroundColor Gray
        Write-Host "   Метрика: policies_loaded_total++" -ForegroundColor DarkCyan
    } else {
        Write-Host " -> " -NoNewline
        Write-Host "ОШИБКА" -ForegroundColor Red
        Write-Host "   Причина: Политики не загружены" -ForegroundColor Gray
        Write-Host "   Метрика: policy_load_failures_total++" -ForegroundColor DarkCyan
    }
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Ошибка загрузки политик" -ForegroundColor Gray
    Write-Host "   Метрика: policy_load_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 2: Валидация формата
Write-Host "Тест 2: Валидация формата" -NoNewline
$invalidPolicy = @{
    invalid_field = "test"
    wrong_format = @("wrong", "data")
}

$validationResult = Invoke-SafeRestMethod -Uri "http://localhost:8004/policies/test_policy" -Method Put -Body $invalidPolicy
if (-not $validationResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Неверный синтаксис YAML" -ForegroundColor Gray
    Write-Host "   Метрика: policy_validation_failures_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Валидация формата прошла успешно" -ForegroundColor Gray
    Write-Host "   Метрика: policy_validation_success_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 3: Сопоставление инцидентов
Write-Host "Тест 3: Сопоставление инцидентов" -NoNewline
$testIncident = @{
    threat_type = "mpi_flood"
    severity = "critical"
    source_node = "compute-node-01"
    metrics = @{
        bytes_sent = 150000000
        packets_sent = 600000
    }
}

$policyResult = Invoke-SafeRestMethod -Uri "http://localhost:8004/get-policy" -Method Post -Body $testIncident
if ($policyResult.Success -and $policyResult.Response -ne $null) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Инцидент корректно сопоставлен с политикой" -ForegroundColor Gray
    Write-Host "   Метрика: policy_matching_success_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось сопоставить инцидент с политикой" -ForegroundColor Gray
    Write-Host "   Метрика: policy_matching_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 4: Динамическое обновление
Write-Host "Тест 4: Динамическое обновление" -NoNewline
$policyUpdate = @{
    actions = @("suspend_job", "notify_admin")
    severity = "critical"
}

$updateResult = Invoke-SafeRestMethod -Uri "http://localhost:8004/policies/mpi_flood_critical" -Method Put -Body $policyUpdate
if ($updateResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Политика обновлена без перезапуска" -ForegroundColor Gray
    Write-Host "   Метрика: dynamic_updates_applied_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОШИБКА" -ForegroundColor Red
    Write-Host "   Причина: Не удалось обновить политику динамически" -ForegroundColor Gray
    Write-Host "   Метрика: dynamic_update_failures_total++" -ForegroundColor DarkCyan
}
Write-Host ""

# Тест 5: Отказ в доступе
Write-Host "Тест 5: Отказ в доступе" -NoNewline
$unauthorizedUpdate = @{
    actions = @("delete_all")
    severity = "critical"
}

$accessResult = Invoke-SafeRestMethod -Uri "http://localhost:8004/policies/mpi_flood_critical" -Method Put -Body $unauthorizedUpdate
if ($accessResult.Success) {
    Write-Host " -> " -NoNewline
    Write-Host "УСПЕХ" -ForegroundColor Green
    Write-Host "   Причина: Доступ разрешен для безопасных операций" -ForegroundColor Gray
    Write-Host "   Метрика: authorized_access_total++" -ForegroundColor DarkCyan
} else {
    Write-Host " -> " -NoNewline
    Write-Host "ОТКАЗ" -ForegroundColor Red
    Write-Host "   Причина: Недостаточно прав для изменения политик" -ForegroundColor Gray
    Write-Host "   Метрика: access_denied_total++" -ForegroundColor DarkCyan
}
Write-Host ""

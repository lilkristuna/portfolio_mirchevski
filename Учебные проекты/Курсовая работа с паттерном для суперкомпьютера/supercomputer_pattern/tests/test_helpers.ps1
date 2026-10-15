# Вспомогательные функции для тестов

# Функция для проверки доступности сервиса
function Test-ServiceHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 5,
        [int]$MaxRetries = 3
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            return @{Success=$true; Response=$response; Error=$null}
        } catch {
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds 1
            } else {
                return @{Success=$false; Response=$null; Error=$_.Exception.Message}
            }
        }
    }
}

# Функция для безопасного выполнения HTTP запроса
function Invoke-SafeRestMethod {
    param(
        [string]$Uri,
        [string]$Method = "Get",
        [object]$Body = $null,
        [hashtable]$Query = $null,
        [string]$ContentType = "application/json",
        [int]$TimeoutSeconds = 10
    )
    
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            TimeoutSec = $TimeoutSeconds
            ErrorAction = "Stop"
        }
        
        if ($Body) {
            if ($Method -eq "Get") {
                # Для GET запросов добавляем параметры в URI
                $queryParts = @()
                foreach ($key in $Body.Keys) {
                    $value = [System.Uri]::EscapeDataString($Body[$key].ToString())
                    $queryParts += "$key=$value"
                }
                if ($queryParts.Count -gt 0) {
                    $separator = if ($Uri -match '\?') { '&' } else { '?' }
                    $params.Uri = "$Uri$separator$($queryParts -join '&')"
                }
            } else {
                $params.Body = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = $ContentType
            }
        } elseif ($Query) {
            $queryParts = @()
            foreach ($key in $Query.Keys) {
                $value = [System.Uri]::EscapeDataString($Query[$key].ToString())
                $queryParts += "$key=$value"
            }
            if ($queryParts.Count -gt 0) {
                $separator = if ($Uri -match '\?') { '&' } else { '?' }
                $params.Uri = "$Uri$separator$($queryParts -join '&')"
            }
        }
        
        $response = Invoke-RestMethod @params
        return @{Success=$true; Response=$response; Error=$null}
    } catch {
        return @{Success=$false; Response=$null; Error=$_.Exception.Message}
    }
}

# Функция для получения Unix timestamp (совместимость с Windows PowerShell)
function Get-UnixTimestamp {
    return [int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds
}

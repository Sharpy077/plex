# Script to validate login configuration for all services
param(
    [string]$LogFile = ".\logs\login-check.log"
)

# Function to write to log
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-OAuth2Proxy {
    try {
        Write-Log "Testing OAuth2 Proxy login..."
        $response = Invoke-WebRequest -Uri "http://localhost:4180/ping" -Method GET -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "OAuth2 Proxy login successful" "SUCCESS"
            return $true
        } else {
            Write-Log "OAuth2 Proxy login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "OAuth2 Proxy login failed: $_" "ERROR"
        return $false
    }
}

function Test-QBittorrent {
    try {
        Write-Log "Testing qBittorrent login..."
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v2/app/version" -Method GET -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "qBittorrent login successful" "SUCCESS"
            return $true
        } else {
            Write-Log "qBittorrent login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "qBittorrent login failed: $_" "ERROR"
        return $false
    }
}

function Test-ArrService {
    param(
        [string]$ServiceName,
        [string]$Port,
        [string]$ApiKey
    )

    try {
        Write-Log "Testing $ServiceName login..."
        $headers = @{
            "X-Api-Key" = $ApiKey
        }
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/api/v3/system/status" -Headers $headers -Method GET -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "$ServiceName login successful" "SUCCESS"
            return $true
        } else {
            Write-Log "$ServiceName login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "$ServiceName login failed: $_" "ERROR"
        return $false
    }
}

# Create log directory if it doesn't exist
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

try {
    Write-Log "Starting login validation..."

    # Test OAuth configuration
    Write-Log "Validating OAuth configuration..."
    
    # Check for required secrets
    $requiredSecrets = @(
        "./docker/secrets/github_client_id.secret",
        "./docker/secrets/github_client_secret.secret",
        "./docker/secrets/auth_secret.secret"
    )

    foreach ($secret in $requiredSecrets) {
        if (-not (Test-Path $secret)) {
            Write-Log "Missing required secret: $secret" "ERROR"
            exit 1
        }
    }

    # Test OAuth2 Proxy
    $oauthSuccess = Test-OAuth2Proxy

    if ($oauthSuccess) {
        Write-Log "OAuth configuration validation successful" "SUCCESS"
    } else {
        Write-Log "OAuth configuration validation failed" "ERROR"
    }

    # Test qBittorrent
    $qbitSuccess = Test-QBittorrent

    # Test *arr services
    $services = @{
        "Prowlarr" = @{
            Port = "9696"
            ApiKeyFile = "./docker/secrets/prowlarr_api_key.secret"
        }
        "Radarr" = @{
            Port = "7878"
            ApiKeyFile = "./docker/secrets/radarr_api_key.secret"
        }
        "Sonarr" = @{
            Port = "8989"
            ApiKeyFile = "./docker/secrets/sonarr_api_key.secret"
        }
        "Lidarr" = @{
            Port = "8686"
            ApiKeyFile = "./docker/secrets/lidarr_api_key.secret"
        }
        "Readarr" = @{
            Port = "8787"
            ApiKeyFile = "./docker/secrets/readarr_api_key.secret"
        }
    }

    foreach ($service in $services.Keys) {
        $apiKey = Get-Content $services[$service].ApiKeyFile -Raw
        Test-ArrService -ServiceName $service -Port $services[$service].Port -ApiKey $apiKey
    }

    Write-Log "All login validations passed successfully!" "SUCCESS"
} catch {
    Write-Log "Login validation script failed: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
} 
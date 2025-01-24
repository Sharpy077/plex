# Script to retrieve API keys from running services
param(
    [Parameter(Mandatory=$false)]
    [string]$SecretsDir = "./docker/secrets"
)

function Get-ServiceApiKey {
    param(
        [string]$Container,
        [string]$ServiceName,
        [string]$ConfigPath
    )
    
    try {
        Write-Host "Getting API key for $ServiceName..."
        
        # Get the config file content
        $configContent = docker exec $Container cat $ConfigPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "$ServiceName config file not found or not accessible" -ForegroundColor Yellow
            return $null
        }
        
        # Look for ApiKey in the XML content
        if ($configContent -match '<ApiKey>([^<]+)</ApiKey>') {
            $apiKey = $matches[1].Trim()
            if ($apiKey) {
                Write-Host "$ServiceName API key found" -ForegroundColor Green
                return $apiKey
            }
        }
        
        Write-Host "$ServiceName API key not found in config" -ForegroundColor Yellow
        return $null
    }
    catch {
        Write-Host "Error getting $ServiceName API key: $_" -ForegroundColor Red
        return $null
    }
}

# Ensure secrets directory exists
New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null

# Service configurations
$services = @(
    @{
        Name = "Prowlarr"
        Container = "prowlarr"
        ConfigPath = "/config/config.xml"
        SecretFile = "prowlarr_api_key.secret"
    },
    @{
        Name = "Radarr"
        Container = "radarr"
        ConfigPath = "/config/config.xml"
        SecretFile = "radarr_api_key.secret"
    },
    @{
        Name = "Sonarr"
        Container = "sonarr"
        ConfigPath = "/config/config.xml"
        SecretFile = "sonarr_api_key.secret"
    },
    @{
        Name = "Lidarr"
        Container = "lidarr"
        ConfigPath = "/config/config.xml"
        SecretFile = "lidarr_api_key.secret"
    },
    @{
        Name = "Readarr"
        Container = "readarr"
        ConfigPath = "/config/config.xml"
        SecretFile = "readarr_api_key.secret"
    }
)

$updatedKeys = 0
foreach ($service in $services) {
    $apiKey = Get-ServiceApiKey -Container $service.Container -ServiceName $service.Name -ConfigPath $service.ConfigPath
    
    if ($apiKey) {
        $secretPath = Join-Path $SecretsDir $service.SecretFile
        Set-Content -Path $secretPath -Value $apiKey -NoNewline
        Write-Host "Updated $($service.Name) API key in $($service.SecretFile)" -ForegroundColor Green
        $updatedKeys++
    }
}

Write-Host "`nAPI key retrieval complete! Updated $updatedKeys keys." -ForegroundColor Green 
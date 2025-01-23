# Get API keys from services
Write-Host "Getting API keys from services..."

# Function to extract API key from config.xml
function Get-ApiKey {
    param (
        [string]$service,
        [string]$configPath
    )
    
    $configFile = docker exec $service cat $configPath
    if ($configFile -match '<ApiKey>([^<]+)</ApiKey>') {
        return $matches[1]
    }
    return $null
}

# Get API keys
$radarrKey = Get-ApiKey -service "radarr" -configPath "/config/config.xml"
$sonarrKey = Get-ApiKey -service "sonarr" -configPath "/config/config.xml"
$lidarrKey = Get-ApiKey -service "lidarr" -configPath "/config/config.xml"

Write-Host "API Keys found:"
Write-Host "Radarr: $radarrKey"
Write-Host "Sonarr: $sonarrKey"
Write-Host "Lidarr: $lidarrKey"

# Save keys to environment variables
$env:RADARR_API_KEY = $radarrKey
$env:SONARR_API_KEY = $sonarrKey
$env:LIDARR_API_KEY = $lidarrKey

Write-Host "`nTo configure services, run:"
Write-Host ".\configure-services.ps1 -RadarrApiKey $radarrKey -SonarrApiKey $sonarrKey -LidarrApiKey $lidarrKey" 
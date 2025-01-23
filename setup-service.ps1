# Setup individual service
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("radarr", "sonarr", "lidarr", "prowlarr", "qbittorrent")]
    [string]$Service,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiKey
)

function Setup-QBittorrent {
    Write-Host "Setting up qBittorrent..."
    
    # Login to qBittorrent
    $loginResult = docker exec qbittorrent curl -s -X POST "http://localhost:8080/api/v2/auth/login" --data "username=admin&password=adminadmin"
    Write-Host "Login result: $loginResult"
    
    # Configure settings
    $config = @{
        save_path = "/downloads/complete"
        temp_path = "/downloads/incomplete"
        create_subfolder_enabled = $true
        start_paused_enabled = $false
    } | ConvertTo-Json -Compress
    
    $result = docker exec qbittorrent curl -s -X POST "http://localhost:8080/api/v2/app/setPreferences" --data "json=$config"
    Write-Host "Configuration result: $result"
}

function Setup-Prowlarr {
    Write-Host "Setting up Prowlarr..."
    
    # Add common indexers
    $indexers = @(
        @{
            name = "1337x"
            implementation = "Torznab"
            configContract = "TorznabSettings"
            fields = @(
                @{ name = "baseUrl"; value = "https://1337x.to" }
            )
        }
    )
    
    foreach ($indexer in $indexers) {
        $indexerConfig = $indexer | ConvertTo-Json -Compress
        $result = docker exec prowlarr curl -s -X POST "http://localhost:9696/api/v1/indexer" -H "Content-Type: application/json" -d $indexerConfig
        Write-Host "Added indexer $($indexer.name): $result"
    }
}

function Setup-Arr-Service {
    param(
        [string]$service,
        [string]$port,
        [string]$apiKey
    )
    
    Write-Host "Setting up $service..."
    
    # Add qBittorrent as download client
    $clientConfig = @{
        name = "qBittorrent"
        implementation = "QBittorrent"
        protocol = "torrent"
        host = "qbittorrent"
        port = 8080
        username = "admin"
        password = "adminadmin"
        category = $service
    } | ConvertTo-Json -Compress
    
    $result = docker exec $service curl -s -X POST "http://localhost:$port/api/v3/downloadclient" -H "X-Api-Key: $apiKey" -H "Content-Type: application/json" -d $clientConfig
    Write-Host "Added download client: $result"
}

# Main setup logic
switch ($Service) {
    "qbittorrent" { Setup-QBittorrent }
    "prowlarr" { Setup-Prowlarr }
    "radarr" { Setup-Arr-Service -service "radarr" -port "7878" -apiKey $ApiKey }
    "sonarr" { Setup-Arr-Service -service "sonarr" -port "8989" -apiKey $ApiKey }
    "lidarr" { Setup-Arr-Service -service "lidarr" -port "8686" -apiKey $ApiKey }
}

Write-Host "Setup complete for $Service" 
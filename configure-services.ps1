# Configure services script
param(
    [Parameter(Mandatory=$true)]
    [string]$RadarrApiKey,
    [Parameter(Mandatory=$true)]
    [string]$SonarrApiKey,
    [Parameter(Mandatory=$true)]
    [string]$LidarrApiKey
)

# Configure qBittorrent
Write-Host "Configuring qBittorrent..."
$qbitConfig = @{
    save_path = "/downloads/complete"
    temp_path = "/downloads/incomplete"
    create_subfolder_enabled = $true
    start_paused_enabled = $false
} | ConvertTo-Json

docker exec qbittorrent curl -X POST "http://localhost:8080/api/v2/auth/login" --data "username=admin&password=adminadmin"
docker exec qbittorrent curl -X POST "http://localhost:8080/api/v2/app/setPreferences" --data "json=$qbitConfig"

# Configure Prowlarr
Write-Host "Configuring Prowlarr..."
$prowlarrApps = @(
    @{
        name = "Radarr"
        implementation = "Radarr"
        baseUrl = "http://radarr:7878"
        apiKey = $RadarrApiKey
    },
    @{
        name = "Sonarr"
        implementation = "Sonarr"
        baseUrl = "http://sonarr:8989"
        apiKey = $SonarrApiKey
    },
    @{
        name = "Lidarr"
        implementation = "Lidarr"
        baseUrl = "http://lidarr:8686"
        apiKey = $LidarrApiKey
    }
)

foreach ($app in $prowlarrApps) {
    $appConfig = @{
        name = $app.name
        implementation = $app.implementation
        baseUrl = $app.baseUrl
        apiKey = $app.apiKey
    } | ConvertTo-Json

    docker exec prowlarr curl -X POST "http://localhost:9696/api/v1/applications" -H "Content-Type: application/json" -d $appConfig
}

# Configure download clients in each service
$services = @(
    @{
        name = "radarr"
        port = "7878"
        apiKey = $RadarrApiKey
    },
    @{
        name = "sonarr"
        port = "8989"
        apiKey = $SonarrApiKey
    },
    @{
        name = "lidarr"
        port = "8686"
        apiKey = $LidarrApiKey
    }
)

foreach ($service in $services) {
    Write-Host "Configuring $($service.name)..."
    $clientConfig = @{
        name = "qBittorrent"
        implementation = "QBittorrent"
        protocol = "torrent"
        host = "qbittorrent"
        port = 8080
        username = "admin"
        password = "adminadmin"
        category = $service.name
    } | ConvertTo-Json

    docker exec $($service.name) curl -X POST "http://localhost:$($service.port)/api/v3/downloadclient" -H "X-Api-Key: $($service.apiKey)" -H "Content-Type: application/json" -d $clientConfig
}

Write-Host "Configuration complete!" 
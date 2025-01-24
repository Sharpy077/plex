# Configure services script
param(
    [Parameter(Mandatory=$true)]
    [string]$RadarrApiKey,
    [Parameter(Mandatory=$true)]
    [string]$SonarrApiKey,
    [Parameter(Mandatory=$true)]
    [string]$LidarrApiKey
)

# Function to execute docker commands with error handling
function Invoke-DockerCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,
        [Parameter(Mandatory=$true)]
        [string]$Command,
        [Parameter(Mandatory=$true)]
        [string]$Description,
        [int]$RetryCount = 3,
        [int]$RetryDelay = 5
    )

    $attempt = 1
    do {
        try {
            Write-Host "Attempting $Description (Attempt $attempt of $RetryCount)..."
            $result = docker exec $Container $Command
            
            if ($LASTEXITCODE -ne 0) {
                throw "Command failed with exit code $LASTEXITCODE"
            }
            
            $response = $result | ConvertFrom-Json -ErrorAction Stop
            Write-Host "$Description completed successfully" -ForegroundColor Green
            return $response
        }
        catch {
            if ($attempt -eq $RetryCount) {
                Write-Error "Failed to $Description after $RetryCount attempts: $_"
                throw
            }
            Write-Warning "Attempt $attempt failed: $_"
            Start-Sleep -Seconds $RetryDelay
            $attempt++
        }
    } while ($attempt -le $RetryCount)
}

# Function to wait for service health
function Wait-ForService {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,
        [Parameter(Mandatory=$true)]
        [string]$HealthEndpoint,
        [int]$TimeoutSeconds = 60
    )
    
    $start = Get-Date
    $healthy = $false
    
    Write-Host "Waiting for $Container to be ready..."
    while (-not $healthy -and ((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $status = docker exec $Container curl -s -f $HealthEndpoint
            if ($LASTEXITCODE -eq 0) {
                $healthy = $true
                Write-Host "$Container is ready" -ForegroundColor Green
            }
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $healthy) {
        throw "$Container failed to become healthy within $TimeoutSeconds seconds"
    }
}

try {
    # Configure qBittorrent
    Write-Host "Configuring qBittorrent..."
    Wait-ForService -Container "qbittorrent" -HealthEndpoint "http://localhost:8080/api/v2/app/version"
    
    $qbitConfig = @{
        save_path = "/downloads/complete"
        temp_path = "/downloads/incomplete"
        create_subfolder_enabled = $true
        start_paused_enabled = $false
    }
    
    # Login to qBittorrent
    $loginResult = Invoke-DockerCommand -Container "qbittorrent" `
        -Command 'curl -s -X POST "http://localhost:8080/api/v2/auth/login" --data "username=admin&password=adminadmin"' `
        -Description "qBittorrent login"
    
    # Set preferences
    $qbitConfigJson = $qbitConfig | ConvertTo-Json -Compress
    Invoke-DockerCommand -Container "qbittorrent" `
        -Command "curl -s -X POST 'http://localhost:8080/api/v2/app/setPreferences' --data 'json=$qbitConfigJson'" `
        -Description "qBittorrent configuration"

    # Configure Prowlarr
    Write-Host "Configuring Prowlarr..."
    Wait-ForService -Container "prowlarr" -HealthEndpoint "http://localhost:9696/api/v1/system/status"
    
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
        $appConfigJson = $app | ConvertTo-Json -Compress
        Invoke-DockerCommand -Container "prowlarr" `
            -Command "curl -s -X POST 'http://localhost:9696/api/v1/applications' -H 'Content-Type: application/json' -d '$appConfigJson'" `
            -Description "Prowlarr $($app.name) configuration"
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
        Wait-ForService -Container $service.name -HealthEndpoint "http://localhost:$($service.port)/api/v3/system/status"
        
        $clientConfig = @{
            name = "qBittorrent"
            implementation = "QBittorrent"
            protocol = "torrent"
            host = "qbittorrent"
            port = 8080
            username = "admin"
            password = "adminadmin"
            category = $service.name
        }
        
        $clientConfigJson = $clientConfig | ConvertTo-Json -Compress
        Invoke-DockerCommand -Container $service.name `
            -Command "curl -s -X POST 'http://localhost:$($service.port)/api/v3/downloadclient' -H 'X-Api-Key: $($service.apiKey)' -H 'Content-Type: application/json' -d '$clientConfigJson'" `
            -Description "$($service.name) download client configuration"
    }

    Write-Host "Configuration completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Configuration failed: $_"
    Write-Host "Stack trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    exit 1
} 
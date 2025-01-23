# Setup Lidarr with proper configuration
Write-Host "Setting up Lidarr..."

# Function to make authenticated requests to Lidarr
function Invoke-LidarrRequest {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Data
    )
    
    $cmd = "curl -s"
    if ($Method -eq "POST") {
        $cmd += " -X POST"
    } elseif ($Method -eq "PUT") {
        $cmd += " -X PUT"
    }
    
    if ($Data) {
        $cmd += " -H 'Content-Type: application/json'"
        $cmd += " --data '$Data'"
    }
    
    $cmd += " -H 'X-Api-Key: \$LIDARR_API_KEY'"
    $cmd += " http://localhost:8686/api/v1$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec lidarr bash -c $cmd
    return $result
}

# Step 1: Wait for Lidarr to be ready
Write-Host "Waiting for Lidarr to be ready..."
Start-Sleep -Seconds 30

# Step 2: Get API Key from config file
$apiKey = docker exec lidarr cat /config/config.xml | Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" | ForEach-Object { $_.Matches.Groups[1].Value }
Write-Host "Found API Key: $apiKey"

if ($apiKey) {
    # Step 3: Configure general settings
    Write-Host "Configuring general settings..."
    $settings = @{
        bindAddress = "*"
        port = 8686
        urlBase = ""
        enableSsl = $false
        launchBrowser = $false
        updateAutomatically = $true
        updateMechanism = "Docker"
        logLevel = "Info"
    } | ConvertTo-Json -Compress

    $result = Invoke-LidarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings
    Write-Host "Settings configuration result: $result"

    # Step 4: Add root folder
    Write-Host "Adding root folder..."
    $rootFolder = @{
        path = "/music"
    } | ConvertTo-Json -Compress

    $result = Invoke-LidarrRequest -Endpoint "/rootfolder" -Method "POST" -Data $rootFolder
    Write-Host "Root folder configuration result: $result"

    # Step 5: Add qBittorrent as download client
    Write-Host "Adding qBittorrent as download client..."
    $qbit = @{
        name = "qBittorrent"
        enable = $true
        protocol = "http"
        host = "qbittorrent"
        port = 8080
        username = "admin"
        password = "adminadmin"
        musicCategory = "lidarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    $result = Invoke-LidarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit
    Write-Host "qBittorrent configuration result: $result"

    # Step 6: Add Prowlarr as indexer proxy
    Write-Host "Adding Prowlarr as indexer proxy..."
    $prowlarr = @{
        name = "Prowlarr"
        enable = $true
        protocol = "http"
        host = "prowlarr"
        port = 9696
        apiKey = "9253c83e14bd4990be4e1c58093631e5"  # From previous Prowlarr setup
        baseUrl = "/api/v1"
        implementation = "Prowlarr"
        configContract = "ProwlarrSettings"
    } | ConvertTo-Json -Compress

    $result = Invoke-LidarrRequest -Endpoint "/indexer" -Method "POST" -Data $prowlarr
    Write-Host "Prowlarr configuration result: $result"

    Write-Host "Setup complete! API Key: $apiKey"
} else {
    Write-Host "Failed to get API key. Please check Lidarr logs and try again."
    exit 1
} 
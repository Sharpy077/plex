# Setup Sonarr with proper configuration
Write-Host "Setting up Sonarr..."

# Function to make authenticated requests to Sonarr
function Invoke-SonarrRequest {
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
    
    $cmd += " -H 'X-Api-Key: \$SONARR_API_KEY'"
    $cmd += " http://localhost:8989/api/v3$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec sonarr bash -c $cmd
    return $result
}

# Step 1: Wait for Sonarr to be ready
Write-Host "Waiting for Sonarr to be ready..."
Start-Sleep -Seconds 30

# Step 2: Get API Key from config file
$apiKey = docker exec sonarr cat /config/config.xml | Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" | ForEach-Object { $_.Matches.Groups[1].Value }
Write-Host "Found API Key: $apiKey"

if ($apiKey) {
    # Step 3: Configure general settings
    Write-Host "Configuring general settings..."
    $settings = @{
        bindAddress = "*"
        port = 8989
        urlBase = ""
        enableSsl = $false
        launchBrowser = $false
        updateAutomatically = $true
        updateMechanism = "Docker"
        logLevel = "Info"
    } | ConvertTo-Json -Compress

    $result = Invoke-SonarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings
    Write-Host "Settings configuration result: $result"

    # Step 4: Add root folder
    Write-Host "Adding root folder..."
    $rootFolder = @{
        path = "/tv"
    } | ConvertTo-Json -Compress

    $result = Invoke-SonarrRequest -Endpoint "/rootfolder" -Method "POST" -Data $rootFolder
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
        tvCategory = "sonarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    $result = Invoke-SonarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit
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

    $result = Invoke-SonarrRequest -Endpoint "/indexer" -Method "POST" -Data $prowlarr
    Write-Host "Prowlarr configuration result: $result"

    Write-Host "Setup complete! API Key: $apiKey"
} else {
    Write-Host "Failed to get API key. Please check Sonarr logs and try again."
    exit 1
} 
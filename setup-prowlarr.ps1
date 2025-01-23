# Setup Prowlarr with proper configuration
Write-Host "Setting up Prowlarr..."

# Function to make authenticated requests to Prowlarr
function Invoke-ProwlarrRequest {
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
    
    $cmd += " -H 'X-Api-Key: \$PROWLARR_API_KEY'"
    $cmd += " http://localhost:9696/api/v1$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec prowlarr bash -c $cmd
    return $result
}

# Step 1: Wait for Prowlarr to be ready
Write-Host "Waiting for Prowlarr to be ready..."
Start-Sleep -Seconds 30

# Step 2: Get API Key from config file
$apiKey = docker exec prowlarr cat /config/config.xml | Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" | ForEach-Object { $_.Matches.Groups[1].Value }
Write-Host "Found API Key: $apiKey"

if ($apiKey) {
    # Step 3: Configure general settings
    Write-Host "Configuring general settings..."
    $settings = @{
        bindAddress = "*"
        port = 9696
        urlBase = ""
        enableSsl = $false
        launchBrowser = $false
        updateAutomatically = $true
        updateMechanism = "Docker"
        logLevel = "Info"
    } | ConvertTo-Json -Compress

    $result = Invoke-ProwlarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings
    Write-Host "Settings configuration result: $result"

    # Step 4: Add qBittorrent as download client
    Write-Host "Adding qBittorrent as download client..."
    $qbit = @{
        name = "qBittorrent"
        enable = $true
        protocol = "http"
        host = "qbittorrent"
        port = 8080
        username = "admin"
        password = "adminadmin"
        category = "prowlarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    $result = Invoke-ProwlarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit
    Write-Host "qBittorrent configuration result: $result"

    Write-Host "Setup complete! API Key: $apiKey"
    Write-Host "You can now use this API key to connect Prowlarr to your other services."
} else {
    Write-Host "Failed to get API key. Please check Prowlarr logs and try again."
    exit 1
} 
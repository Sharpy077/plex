# Setup Readarr with proper configuration
Write-Host "Setting up Readarr..."

# Function to make authenticated requests to Readarr
function Invoke-ReadarrRequest {
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
    
    $cmd += " -H 'X-Api-Key: \$READARR_API_KEY'"
    $cmd += " http://localhost:8787/api/v1$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec readarr bash -c $cmd
    return $result
}

# Step 1: Wait for Readarr to be ready
Write-Host "Waiting for Readarr to be ready..."
Start-Sleep -Seconds 30

# Step 2: Get API Key from config file
$apiKey = docker exec readarr cat /config/config.xml | Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" | ForEach-Object { $_.Matches.Groups[1].Value }
Write-Host "Found API Key: $apiKey"

if ($apiKey) {
    # Step 3: Configure general settings
    Write-Host "Configuring general settings..."
    $settings = @{
        bindAddress = "*"
        port = 8787
        urlBase = ""
        enableSsl = $false
        launchBrowser = $false
        updateAutomatically = $true
        updateMechanism = "Docker"
        logLevel = "Info"
    } | ConvertTo-Json -Compress

    $result = Invoke-ReadarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings
    Write-Host "Settings configuration result: $result"

    # Step 4: Add root folder
    Write-Host "Adding root folder..."
    $rootFolder = @{
        path = "/books"
    } | ConvertTo-Json -Compress

    $result = Invoke-ReadarrRequest -Endpoint "/rootfolder" -Method "POST" -Data $rootFolder
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
        bookCategory = "readarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    $result = Invoke-ReadarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit
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

    $result = Invoke-ReadarrRequest -Endpoint "/indexer" -Method "POST" -Data $prowlarr
    Write-Host "Prowlarr configuration result: $result"

    Write-Host "Setup complete! API Key: $apiKey"
} else {
    Write-Host "Failed to get API key. Please check Readarr logs and try again."
    exit 1
} 
# Setup Bazarr with proper configuration
Write-Host "Setting up Bazarr..."

# Function to make authenticated requests to Bazarr
function Invoke-BazarrRequest {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Data
    )
    
    # First get the API key from config.yaml
    $apiKey = docker exec bazarr cat /config/config/config.yaml | Select-String -Pattern "^auth:apikey:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value }
    if (-not $apiKey) {
        Write-Host "API key not found in config.yaml, checking if we need to initialize Bazarr first..."
        # Try to initialize Bazarr by accessing the web interface
        docker exec bazarr curl -s "http://localhost:6767"
        Start-Sleep -Seconds 5
        $apiKey = docker exec bazarr cat /config/config/config.yaml | Select-String -Pattern "^auth:apikey:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value }
    }
    
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
    
    if ($apiKey) {
        $cmd += " -H 'X-Api-Key: $apiKey'"
    }
    $cmd += " http://localhost:6767/api/v1$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec bazarr bash -c $cmd
    return $result
}

# Step 1: Wait for Bazarr to be ready and initialized
Write-Host "Waiting for Bazarr to be ready..."
Start-Sleep -Seconds 30

# Step 2: Configure general settings
Write-Host "Configuring general settings..."
$settings = @{
    base_url = ""
    port = 6767
    enable_ssl = $false
    auto_update = $true
    update_type = "docker"
    path_mappings = @(
        @{
            movie = "/movies"
            tv = "/tv"
        }
    )
} | ConvertTo-Json -Compress

$result = Invoke-BazarrRequest -Endpoint "/settings/general" -Method "POST" -Data $settings
Write-Host "Settings configuration result: $result"

# Step 3: Configure Sonarr connection
Write-Host "Configuring Sonarr connection..."
$sonarr = @{
    name = "Sonarr"
    apikey = "91cdc4952772465eb88845b2a8067a59"  # From previous Sonarr setup
    host = "http://sonarr:8989"
    base_url = ""
    ssl = $false
    enabled = $true
} | ConvertTo-Json -Compress

$result = Invoke-BazarrRequest -Endpoint "/settings/sonarr" -Method "POST" -Data $sonarr
Write-Host "Sonarr configuration result: $result"

# Step 4: Configure Radarr connection
Write-Host "Configuring Radarr connection..."
$radarr = @{
    name = "Radarr"
    apikey = "1f486948b4fd4fe9913515feac77a40e"  # From previous Radarr setup
    host = "http://radarr:7878"
    base_url = ""
    ssl = $false
    enabled = $true
} | ConvertTo-Json -Compress

$result = Invoke-BazarrRequest -Endpoint "/settings/radarr" -Method "POST" -Data $radarr
Write-Host "Radarr configuration result: $result"

# Step 5: Configure subtitle providers
Write-Host "Configuring subtitle providers..."
$providers = @{
    opensubtitles = @{
        enabled = $true
        languages = @("eng")
        hearing_impaired = $true
        minimum_score = 90
    }
    subscene = @{
        enabled = $true
        languages = @("eng")
    }
} | ConvertTo-Json -Compress

$result = Invoke-BazarrRequest -Endpoint "/settings/providers" -Method "POST" -Data $providers
Write-Host "Providers configuration result: $result"

Write-Host "Setup complete!" 
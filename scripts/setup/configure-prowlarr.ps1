# Configure Prowlarr and connect it to Sonarr
param (
    [string]$ProwlarrUrl = "http://prowlarr:9696",
    [string]$SonarrUrl = "http://sonarr:8989",
    [string]$ProwlarrApiKey = $(Get-Content "/run/secrets/prowlarr_api_key.secret"),
    [string]$SonarrApiKey = $(Get-Content "/run/secrets/sonarr_api_key.secret")
)

# Function to wait for service to be ready
function Wait-ForService {
    param (
        [string]$Url,
        [int]$TimeoutSeconds = 300
    )
    $start = Get-Date
    $ready = $false

    Write-Host "Waiting for service at $Url to be ready..."
    while (-not $ready -and ((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $response = Invoke-WebRequest -Uri "$Url/api/v3/system/status" -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $ready = $true
                Write-Host "Service is ready!"
            }
        }
        catch {
            Write-Host "Service not ready yet, waiting..."
            Start-Sleep -Seconds 5
        }
    }

    if (-not $ready) {
        throw "Service did not become ready within timeout period"
    }
}

# Wait for both services to be ready
Wait-ForService -Url $ProwlarrUrl
Wait-ForService -Url $SonarrUrl

# Configure Prowlarr application for Sonarr
$applicationData = @{
    name = "Sonarr"
    syncLevel = "fullSync"
    implementationName = "Sonarr"
    implementation = "Sonarr"
    configContract = "SonarrSettings"
    fields = @(
        @{
            name = "prowlarrUrl"
            value = $ProwlarrUrl
        },
        @{
            name = "baseUrl"
            value = $SonarrUrl
        },
        @{
            name = "apiKey"
            value = $SonarrApiKey
        },
        @{
            name = "syncCategories"
            value = @(
                5000,  # TV
                5010,  # TV WEB-DL
                5020,  # TV HD
                5030,  # TV SD
                5040,  # TV UHD
                5045   # TV Other
            )
        }
    )
    tags = @()
}

# Add Sonarr to Prowlarr
try {
    $headers = @{
        "X-Api-Key" = $ProwlarrApiKey
        "Content-Type" = "application/json"
    }

    $response = Invoke-RestMethod -Uri "$ProwlarrUrl/api/v1/applications" -Method Post -Body ($applicationData | ConvertTo-Json -Depth 10) -Headers $headers
    Write-Host "Successfully configured Prowlarr to connect with Sonarr"
}
catch {
    Write-Error "Failed to configure Prowlarr: $_"
    exit 1
}

# Add some common indexers
$indexers = @(
    @{
        name = "1337x"
        implementation = "1337x"
        configContract = "1337xSettings"
        fields = @(
            @{
                name = "baseUrl"
                value = "https://1337x.to"
            }
        )
    }
)

foreach ($indexer in $indexers) {
    try {
        $response = Invoke-RestMethod -Uri "$ProwlarrUrl/api/v1/indexer" -Method Post -Body ($indexer | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Successfully added indexer: $($indexer.name)"
    }
    catch {
        Write-Warning "Failed to add indexer $($indexer.name): $_"
    }
}
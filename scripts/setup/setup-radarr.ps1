<#
.SYNOPSIS
    Configures Radarr container with proper settings, download client, and indexer.

.DESCRIPTION
    This script performs the initial setup and configuration of Radarr including:
    - Configuring general settings (ports, SSL, updates)
    - Setting up the root movies folder
    - Integrating with qBittorrent as download client
    - Integrating with Prowlarr as indexer proxy
    The script assumes Radarr is running in a Docker container named 'radarr'.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    - RADARR_API_KEY: API key for Radarr (automatically retrieved from config)
    - PROWLARR_API_KEY: API key for Prowlarr integration

.DEPENDENCIES
    Required dependencies:
    - Docker (running container named 'radarr')
    - PowerShell 5.1 or higher
    - curl (available in container)

.EXAMPLE
    .\setup-radarr.ps1

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function definitions
function Initialize-Environment {
    # Verify Docker container is running
    $container = docker ps -q -f name=radarr
    if (-not $container) {
        throw "Radarr container is not running"
    }

    # Wait for Radarr to be ready
    Write-Host "Waiting for Radarr to be ready..."
    Start-Sleep -Seconds 30
}

function Get-RadarrApiKey {
    $apiKey = docker exec radarr cat /config/config.xml |
              Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" |
              ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $apiKey) {
        throw "Failed to retrieve Radarr API key"
    }
    return $apiKey
}

function Invoke-RadarrRequest {
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

    $cmd += " -H 'X-Api-Key: \$RADARR_API_KEY'"
    $cmd += " http://localhost:7878/api/v3$Endpoint"

    Write-Host "Executing API request to: $Endpoint"
    $result = docker exec radarr bash -c $cmd

    if (-not $result) {
        throw "Failed to execute Radarr API request: $Endpoint"
    }
    return $result
}

function Set-RadarrConfiguration {
    param (
        [string]$ApiKey
    )

    # Configure general settings
    Write-Host "Configuring general settings..."
    $settings = @{
        bindAddress = "*"
        port = 7878
        urlBase = ""
        enableSsl = $false
        launchBrowser = $false
        updateAutomatically = $true
        updateMechanism = "Docker"
        logLevel = "Info"
    } | ConvertTo-Json -Compress

    Invoke-RadarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings

    # Add root folder
    Write-Host "Adding root folder..."
    $rootFolder = @{
        path = "/movies"
    } | ConvertTo-Json -Compress

    Invoke-RadarrRequest -Endpoint "/rootfolder" -Method "POST" -Data $rootFolder

    # Add qBittorrent
    Write-Host "Adding qBittorrent as download client..."
    $qbit = @{
        name = "qBittorrent"
        enable = $true
        protocol = "http"
        host = "qbittorrent"
        port = 8080
        username = "admin"
        password = "adminadmin"
        movieCategory = "radarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    Invoke-RadarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit

    # Add Prowlarr
    Write-Host "Adding Prowlarr as indexer proxy..."
    $prowlarr = @{
        name = "Prowlarr"
        enable = $true
        protocol = "http"
        host = "prowlarr"
        port = 9696
        apiKey = $env:PROWLARR_API_KEY
        baseUrl = "/api/v1"
        implementation = "Prowlarr"
        configContract = "ProwlarrSettings"
    } | ConvertTo-Json -Compress

    Invoke-RadarrRequest -Endpoint "/indexer" -Method "POST" -Data $prowlarr
}

function Main {
    try {
        Initialize-Environment
        $apiKey = Get-RadarrApiKey
        Set-RadarrConfiguration -ApiKey $apiKey
        Write-Host "Radarr setup completed successfully!"
    }
    catch {
        Write-Error "Error during Radarr setup: $_"
        exit 1
    }
}

# Script execution
Main
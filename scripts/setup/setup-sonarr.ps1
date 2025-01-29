<#
.SYNOPSIS
    Configures Sonarr container with proper settings, download client, and indexer.

.DESCRIPTION
    This script performs the initial setup and configuration of Sonarr including:
    - Configuring general settings (ports, SSL, updates)
    - Setting up the root TV shows folder
    - Integrating with qBittorrent as download client
    - Integrating with Prowlarr as indexer proxy
    The script assumes Sonarr is running in a Docker container named 'sonarr'.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    - SONARR_API_KEY: API key for Sonarr (automatically retrieved from config)
    - PROWLARR_API_KEY: API key for Prowlarr integration

.DEPENDENCIES
    Required dependencies:
    - Docker (running container named 'sonarr')
    - PowerShell 5.1 or higher
    - curl (available in container)

.EXAMPLE
    .\setup-sonarr.ps1

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
    $container = docker ps -q -f name=sonarr
    if (-not $container) {
        throw "Sonarr container is not running"
    }

    # Wait for Sonarr to be ready
    Write-Host "Waiting for Sonarr to be ready..."
    Start-Sleep -Seconds 30
}

function Get-SonarrApiKey {
    $apiKey = docker exec sonarr cat /config/config.xml |
              Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" |
              ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $apiKey) {
        throw "Failed to retrieve Sonarr API key"
    }
    return $apiKey
}

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

    Write-Host "Executing API request to: $Endpoint"
    $result = docker exec sonarr bash -c $cmd

    if (-not $result) {
        throw "Failed to execute Sonarr API request: $Endpoint"
    }
    return $result
}

function Set-SonarrConfiguration {
    param (
        [string]$ApiKey
    )

    # Configure general settings
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

    Invoke-SonarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings

    # Add root folder
    Write-Host "Adding root folder..."
    $rootFolder = @{
        path = "/tv"
    } | ConvertTo-Json -Compress

    Invoke-SonarrRequest -Endpoint "/rootfolder" -Method "POST" -Data $rootFolder

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
        tvCategory = "sonarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    Invoke-SonarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit

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

    Invoke-SonarrRequest -Endpoint "/indexer" -Method "POST" -Data $prowlarr
}

function Main {
    try {
        Initialize-Environment
        $apiKey = Get-SonarrApiKey
        Set-SonarrConfiguration -ApiKey $apiKey
        Write-Host "Sonarr setup completed successfully!"
    }
    catch {
        Write-Error "Error during Sonarr setup: $_"
        exit 1
    }
}

# Script execution
Main
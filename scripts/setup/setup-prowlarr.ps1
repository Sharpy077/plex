<#
.SYNOPSIS
    Configures Prowlarr container with proper settings and download client integration.

.DESCRIPTION
    This script performs the initial setup and configuration of Prowlarr including:
    - Configuring general settings (ports, SSL, updates)
    - Integrating with qBittorrent as download client
    - Retrieving API key for other services to use
    The script assumes Prowlarr is running in a Docker container named 'prowlarr'.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    - PROWLARR_API_KEY: API key for Prowlarr (automatically retrieved from config)

.DEPENDENCIES
    Required dependencies:
    - Docker (running container named 'prowlarr')
    - PowerShell 5.1 or higher
    - curl (available in container)

.EXAMPLE
    .\setup-prowlarr.ps1

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
    $container = docker ps -q -f name=prowlarr
    if (-not $container) {
        throw "Prowlarr container is not running"
    }

    # Wait for Prowlarr to be ready
    Write-Host "Waiting for Prowlarr to be ready..."
    Start-Sleep -Seconds 30
}

function Get-ProwlarrApiKey {
    $apiKey = docker exec prowlarr cat /config/config.xml |
              Select-String -Pattern "<ApiKey>([^<]+)</ApiKey>" |
              ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $apiKey) {
        throw "Failed to retrieve Prowlarr API key"
    }

    # Store the API key for other services to use
    [Environment]::SetEnvironmentVariable('PROWLARR_API_KEY', $apiKey, 'User')
    Write-Host "API Key has been stored in PROWLARR_API_KEY environment variable"

    return $apiKey
}

function Invoke-ProwlarrRequest {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Data,
        [string]$ApiKey
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

    $cmd += " -H 'X-Api-Key: $ApiKey'"
    $cmd += " http://localhost:9696/api/v1$Endpoint"

    Write-Host "Executing API request to: $Endpoint"
    $result = docker exec prowlarr bash -c $cmd

    if (-not $result) {
        throw "Failed to execute Prowlarr API request: $Endpoint"
    }
    return $result
}

function Set-ProwlarrConfiguration {
    param (
        [string]$ApiKey
    )

    # Configure general settings
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

    Invoke-ProwlarrRequest -Endpoint "/config/host" -Method "PUT" -Data $settings -ApiKey $ApiKey

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
        category = "prowlarr"
        priority = 1
        implementation = "QBittorrent"
        configContract = "QBittorrentSettings"
    } | ConvertTo-Json -Compress

    Invoke-ProwlarrRequest -Endpoint "/downloadclient" -Method "POST" -Data $qbit -ApiKey $ApiKey
}

function Main {
    try {
        Initialize-Environment
        $apiKey = Get-ProwlarrApiKey
        Set-ProwlarrConfiguration -ApiKey $apiKey
        Write-Host "Prowlarr setup completed successfully!"
        Write-Host "The API key has been stored in the PROWLARR_API_KEY environment variable for other services to use."
    }
    catch {
        Write-Error "Error during Prowlarr setup: $_"
        exit 1
    }
}

# Script execution
Main
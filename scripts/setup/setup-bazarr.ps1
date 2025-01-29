<#
.SYNOPSIS
    Configures Bazarr container with proper settings and media server integrations.

.DESCRIPTION
    This script performs the initial setup and configuration of Bazarr including:
    - Configuring general settings (ports, SSL, updates)
    - Setting up path mappings for movies and TV shows
    - Integrating with Sonarr for TV show subtitles
    - Integrating with Radarr for movie subtitles
    - Configuring subtitle providers (OpenSubtitles, Subscene)
    The script assumes Bazarr is running in a Docker container named 'bazarr'.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    - SONARR_API_KEY: API key for Sonarr integration
    - RADARR_API_KEY: API key for Radarr integration

.DEPENDENCIES
    Required dependencies:
    - Docker (running container named 'bazarr')
    - PowerShell 5.1 or higher
    - curl (available in container)

.EXAMPLE
    .\setup-bazarr.ps1

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
    $container = docker ps -q -f name=bazarr
    if (-not $container) {
        throw "Bazarr container is not running"
    }

    # Wait for Bazarr to be ready
    Write-Host "Waiting for Bazarr to be ready..."
    Start-Sleep -Seconds 30
}

function Get-BazarrApiKey {
    # First get the API key from config.yaml
    $apiKey = docker exec bazarr cat /config/config/config.yaml |
              Select-String -Pattern "^auth:apikey:\s*(.+)$" |
              ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $apiKey) {
        Write-Host "API key not found in config.yaml, initializing Bazarr..."
        # Try to initialize Bazarr by accessing the web interface
        docker exec bazarr curl -s "http://localhost:6767"
        Start-Sleep -Seconds 5
        $apiKey = docker exec bazarr cat /config/config/config.yaml |
                  Select-String -Pattern "^auth:apikey:\s*(.+)$" |
                  ForEach-Object { $_.Matches.Groups[1].Value }

        if (-not $apiKey) {
            throw "Failed to retrieve or generate Bazarr API key"
        }
    }
    return $apiKey
}

function Invoke-BazarrRequest {
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
    $cmd += " http://localhost:6767/api/v1$Endpoint"

    Write-Host "Executing API request to: $Endpoint"
    $result = docker exec bazarr bash -c $cmd

    if (-not $result) {
        throw "Failed to execute Bazarr API request: $Endpoint"
    }
    return $result
}

function Set-BazarrConfiguration {
    param (
        [string]$ApiKey
    )

    # Configure general settings
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

    Invoke-BazarrRequest -Endpoint "/settings/general" -Method "POST" -Data $settings -ApiKey $ApiKey

    # Configure Sonarr connection
    Write-Host "Configuring Sonarr connection..."
    $sonarr = @{
        name = "Sonarr"
        apikey = $env:SONARR_API_KEY
        host = "http://sonarr:8989"
        base_url = ""
        ssl = $false
        enabled = $true
    } | ConvertTo-Json -Compress

    Invoke-BazarrRequest -Endpoint "/settings/sonarr" -Method "POST" -Data $sonarr -ApiKey $ApiKey

    # Configure Radarr connection
    Write-Host "Configuring Radarr connection..."
    $radarr = @{
        name = "Radarr"
        apikey = $env:RADARR_API_KEY
        host = "http://radarr:7878"
        base_url = ""
        ssl = $false
        enabled = $true
    } | ConvertTo-Json -Compress

    Invoke-BazarrRequest -Endpoint "/settings/radarr" -Method "POST" -Data $radarr -ApiKey $ApiKey

    # Configure subtitle providers
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

    Invoke-BazarrRequest -Endpoint "/settings/providers" -Method "POST" -Data $providers -ApiKey $ApiKey
}

function Main {
    try {
        Initialize-Environment
        $apiKey = Get-BazarrApiKey
        Set-BazarrConfiguration -ApiKey $apiKey
        Write-Host "Bazarr setup completed successfully!"
    }
    catch {
        Write-Error "Error during Bazarr setup: $_"
        exit 1
    }
}

# Script execution
Main
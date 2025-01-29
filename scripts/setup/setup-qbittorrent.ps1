<#
.SYNOPSIS
    Configures qBittorrent container with proper authentication and download settings.

.DESCRIPTION
    This script performs the initial setup and configuration of qBittorrent including:
    - Setting up authentication with secure credentials
    - Configuring download paths and behavior
    - Setting up web UI access
    - Configuring performance and storage settings
    The script assumes qBittorrent is running in a Docker container named 'qbittorrent'.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    None required, but the following are configurable:
    - QBIT_USERNAME: Username for web UI (defaults to 'admin')
    - QBIT_PASSWORD: Password for web UI (defaults to 'adminadmin')

.DEPENDENCIES
    Required dependencies:
    - Docker (running container named 'qbittorrent')
    - PowerShell 5.1 or higher
    - curl (available in container)

.EXAMPLE
    .\setup-qbittorrent.ps1

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
    $container = docker ps -q -f name=qbittorrent
    if (-not $container) {
        throw "qBittorrent container is not running"
    }

    # Wait for qBittorrent to be ready
    Write-Host "Waiting for qBittorrent to be ready..."
    Start-Sleep -Seconds 30
}

function Get-QBitAuthCookie {
    Write-Host "Authenticating with temporary password..."
    $auth = docker exec qbittorrent curl -s -i -X POST --data "username=admin&password=CtJKzU4SN" http://localhost:8080/api/v2/auth/login

    # Extract the cookie from the response
    $cookie = ($auth -split "`n" | Select-String "SID=") -replace "Set-Cookie: ", "" -replace ";.*", ""

    if (-not $cookie) {
        throw "Failed to authenticate with qBittorrent"
    }

    Write-Host "Successfully authenticated with qBittorrent"
    return $cookie
}

function Invoke-QBitRequest {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Data,
        [string]$Cookie
    )

    $cmd = "curl -s"
    if ($Method -eq "POST") {
        $cmd += " -X POST"
    }

    if ($Data) {
        $cmd += " --data `"$Data`""
    }

    if ($Cookie) {
        $cmd += " -b `"$Cookie`""
    }

    $cmd += " http://localhost:8080$Endpoint"

    Write-Host "Executing API request to: $Endpoint"
    $result = docker exec qbittorrent bash -c $cmd

    if (-not $result -and $Method -eq "POST") {
        throw "Failed to execute qBittorrent API request: $Endpoint"
    }
    return $result
}

function Set-QBitConfiguration {
    param (
        [string]$Cookie
    )

    # Get configuration values from environment or use defaults
    $username = $env:QBIT_USERNAME ?? "admin"
    $password = $env:QBIT_PASSWORD ?? "adminadmin"

    Write-Host "Configuring qBittorrent settings..."
    $settings = @{
        "save_path" = "/downloads/complete"
        "temp_path" = "/downloads/incomplete"
        "temp_path_enabled" = "true"
        "preallocate_all" = "true"
        "incomplete_files_ext" = "true"
        "create_subfolder_enabled" = "true"
        "start_paused_enabled" = "false"
        "auto_delete_mode" = "0"
        "web_ui_username" = $username
        "web_ui_password" = $password
        "max_active_downloads" = 5
        "max_active_torrents" = 10
        "max_active_uploads" = 5
        "queueing_enabled" = "true"
        "encryption" = 1  # Prefer encryption
        "proxy_peer_connections" = "true"
        "proxy_torrents" = "true"
        "proxy_type" = 0  # None by default
    } | ConvertTo-Json -Compress

    # Escape quotes for curl command
    $jsonSettings = $settings.Replace('"', '\"')
    $data = "json=$jsonSettings"

    Write-Host "Applying settings..."
    Start-Sleep -Seconds 1  # Brief pause to ensure settings can be applied
    Invoke-QBitRequest -Endpoint "/api/v2/app/setPreferences" -Method "POST" -Data $data -Cookie $Cookie
}

function Main {
    try {
        Initialize-Environment
        $cookie = Get-QBitAuthCookie
        Set-QBitConfiguration -Cookie $cookie
        Write-Host "qBittorrent setup completed successfully!"
        Write-Host "You can now access the web UI with the configured credentials."
    }
    catch {
        Write-Error "Error during qBittorrent setup: $_"
        exit 1
    }
}

# Script execution
Main
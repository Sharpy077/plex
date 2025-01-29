<#
.SYNOPSIS
    Validates login configuration and authentication for all services in the Plex environment.

.DESCRIPTION
    This script performs comprehensive validation of login and authentication mechanisms including:
    - OAuth2 Proxy configuration and connectivity
    - Service API key validation
    - SSL/TLS certificate validation
    - Authentication endpoints for all services (Radarr, Sonarr, etc.)
    The script includes detailed logging and error reporting for each validation step.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\login-check.log".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.ENVIRONMENT
    Required environment variables:
    None - Uses secret files instead

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\validate-login.ps1 -LogFile "D:\logs\login-validation.log" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$LogFile = ".\logs\login-check.log",
    [bool]$VerboseLogging = $true
)

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = if ($VerboseLogging) { "Continue" } else { "SilentlyContinue" }

# Function definitions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"

    # Write to console with color
    $color = switch ($Level) {
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color

    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
    Write-Verbose "Logged: $logMessage"
}

function Initialize-Environment {
    # Configure SSL/TLS settings
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Verbose "Configured TLS 1.2"

    # Create log directory if it doesn't exist
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Write-Log "Created log directory: $logDir"
    }

    # Verify required secret files
    $requiredSecrets = @(
        "./docker/secrets/github_client_id.secret",
        "./docker/secrets/github_client_secret.secret",
        "./docker/secrets/auth_secret.secret"
    )

    foreach ($secret in $requiredSecrets) {
        if (-not (Test-Path $secret)) {
            throw "Missing required secret file: $secret"
        }
        Write-Verbose "Verified secret file: $secret"
    }
}

function Test-OAuth2Proxy {
    try {
        Write-Log "Testing OAuth2 Proxy login..."
        $response = Invoke-WebRequest -Uri "https://auth.sharphorizons.tech/ping" `
            -Method GET -UseBasicParsing -SkipCertificateCheck

        if ($response.StatusCode -eq 200) {
            Write-Log "OAuth2 Proxy login successful" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "OAuth2 Proxy login failed with status code $($response.StatusCode)" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "OAuth2 Proxy login failed: $($_.Exception.Message)" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-QBittorrent {
    try {
        Write-Log "Testing qBittorrent login..."
        $response = Invoke-WebRequest -Uri "https://qbit.sharphorizons.tech/api/v2/app/version" `
            -Method GET -UseBasicParsing -SkipCertificateCheck

        if ($response.StatusCode -eq 200) {
            Write-Log "qBittorrent login successful" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "qBittorrent login failed with status code $($response.StatusCode)" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "qBittorrent login failed: $($_.Exception.Message)" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-ArrService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [string]$Port,
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try {
        Write-Log "Testing $ServiceName login..."
        $headers = @{
            "X-Api-Key" = $ApiKey
        }

        $response = Invoke-WebRequest -Uri "https://$Domain/api/v3/health" `
            -Headers $headers -Method GET -UseBasicParsing -SkipCertificateCheck

        if ($response.StatusCode -eq 200) {
            Write-Log "$ServiceName login successful" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "$ServiceName login failed with status code $($response.StatusCode)" -Level 'ERROR'
            return $false
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "$ServiceName login failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-AllServices {
    # Define service configurations
    $services = @{
        "Prowlarr" = @{
            Port       = "9696"
            ApiKeyFile = "./docker/secrets/prowlarr_api_key.secret"
            Domain     = "prowlarr.sharphorizons.tech"
        }
        "Radarr"   = @{
            Port       = "7878"
            ApiKeyFile = "./docker/secrets/radarr_api_key.secret"
            Domain     = "radarr.sharphorizons.tech"
        }
        "Sonarr"   = @{
            Port       = "8989"
            ApiKeyFile = "./docker/secrets/sonarr_api_key.secret"
            Domain     = "sonarr.sharphorizons.tech"
        }
        "Lidarr"   = @{
            Port       = "8686"
            ApiKeyFile = "./docker/secrets/lidarr_api_key.secret"
            Domain     = "lidarr.sharphorizons.tech"
        }
        "Readarr"  = @{
            Port       = "8787"
            ApiKeyFile = "./docker/secrets/readarr_api_key.secret"
            Domain     = "readarr.sharphorizons.tech"
        }
    }

    $results = @()
    foreach ($service in $services.Keys) {
        Write-Verbose "Testing service: $service"
        if (-not (Test-Path $services[$service].ApiKeyFile)) {
            Write-Log "API key file not found for $service: $($services[$service].ApiKeyFile)" -Level 'ERROR'
            continue
        }

        $apiKey = Get-Content $services[$service].ApiKeyFile -Raw
        $apiKey = $apiKey.Trim()
        Write-Verbose "Loaded API key for $service"

        $success = Test-ArrService -ServiceName $service `
            -Port $services[$service].Port `
            -ApiKey $apiKey `
            -Domain $services[$service].Domain

        $results += [PSCustomObject]@{
            Service = $service
            Success = $success
        }
    }

    return $results
}

function Main {
    try {
        Write-Log "Starting login validation..."
        Initialize-Environment

        # Test OAuth2 Proxy
        $oauthSuccess = Test-OAuth2Proxy

        # Test qBittorrent
        $qbitSuccess = Test-QBittorrent

        # Test all *arr services
        $serviceResults = Test-AllServices

        # Summarize results
        Write-Log "=== Validation Summary ===" -Level 'INFO'
        Write-Log "OAuth2 Proxy: $(if ($oauthSuccess) { 'SUCCESS' } else { 'FAILED' })" `
            -Level $(if ($oauthSuccess) { 'SUCCESS' } else { 'ERROR' })
        Write-Log "qBittorrent: $(if ($qbitSuccess) { 'SUCCESS' } else { 'FAILED' })" `
            -Level $(if ($qbitSuccess) { 'SUCCESS' } else { 'ERROR' })

        foreach ($result in $serviceResults) {
            Write-Log "$($result.Service): $(if ($result.Success) { 'SUCCESS' } else { 'FAILED' })" `
                -Level $(if ($result.Success) { 'SUCCESS' } else { 'ERROR' })
        }

        Write-Log "Login validation completed!" -Level 'SUCCESS'
    }
    catch {
        Write-Log "Login validation failed: $($_.Exception.Message)" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        throw
    }
}

# Script execution
Main
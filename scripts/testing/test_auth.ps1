<#
.SYNOPSIS
    Tests OAuth2 authentication flow and endpoint security for all services.

.DESCRIPTION
    This script performs comprehensive testing of the authentication system including:
    - OAuth2 Proxy health checks
    - Protected endpoint validation
    - Plex authentication requirements
    - OAuth2 callback functionality
    - Authentication configuration validation
    The script includes detailed logging and status reporting for each test.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\auth-test.log".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\test_auth.ps1 -LogFile "D:\logs\auth-test.log" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$LogFile = ".\logs\auth-test.log",
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
    # Create log directory if it doesn't exist
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Write-Log "Created log directory: $logDir" -Level 'SUCCESS'
    }
}

function Test-Endpoint {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [switch]$ExpectAuth,
        [switch]$ExpectPlexAuth
    )

    Write-Log "Testing $Name ($Url)..."
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -SkipCertificateCheck -MaximumRedirection 0 -ErrorAction Stop
        $statusCode = $response.StatusCode
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        else {
            Write-Log "$Name - Connection failed: $($_.Exception.Message)" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "$Name - Unexpected error: $($_.Exception.Message)" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }

    if ($ExpectAuth) {
        # Should redirect to auth (302) or require auth (401)
        if ($statusCode -in @(302, 401)) {
            Write-Log "$Name - Authentication required (Status: $statusCode)" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "$Name - Expected auth requirement, got status $statusCode" -Level 'ERROR'
            return $false
        }
    }
    elseif ($ExpectPlexAuth) {
        # Plex should return 401 for its own auth
        if ($statusCode -eq 401) {
            Write-Log "$Name - Plex authentication required (Status: 401)" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "$Name - Expected Plex auth requirement (401), got status $statusCode" -Level 'ERROR'
            return $false
        }
    }
    else {
        # Should allow access (200)
        if ($statusCode -eq 200) {
            Write-Log "$Name - Access allowed (Status: 200)" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "$Name - Expected 200, got status $statusCode" -Level 'ERROR'
            return $false
        }
    }
}

function Test-OAuth2Proxy {
    Write-Log "=== Testing OAuth2 Proxy Health ===" -Level 'INFO'
    $results = @{
        Success = 0
        Failed = 0
        Ports = @()
    }

    # Test internal access (from Docker network)
    try {
        $response = Invoke-WebRequest -Uri "http://oauth2-proxy:4180/ping" -UseBasicParsing -SkipCertificateCheck
        if ($response.StatusCode -eq 200) {
            Write-Log "Internal access - Healthy" -Level 'SUCCESS'
            $results.Success++
            $results.Ports += [PSCustomObject]@{
                Access = "Internal"
                Status = "Healthy"
            }
        }
        else {
            Write-Log "Internal access - Unhealthy (Status: $($response.StatusCode))" -Level 'ERROR'
            $results.Failed++
            $results.Ports += [PSCustomObject]@{
                Access = "Internal"
                Status = "Unhealthy"
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Internal access - Error: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        $results.Failed++
        $results.Ports += [PSCustomObject]@{
            Access = "Internal"
            Status = "Error"
        }
    }

    # Test external access (through Traefik)
    try {
        $response = Invoke-WebRequest -Uri "https://auth.sharphorizons.tech/ping" -UseBasicParsing -SkipCertificateCheck
        if ($response.StatusCode -eq 200) {
            Write-Log "External access - Healthy" -Level 'SUCCESS'
            $results.Success++
            $results.Ports += [PSCustomObject]@{
                Access = "External"
                Status = "Healthy"
            }
        }
        else {
            Write-Log "External access - Unhealthy (Status: $($response.StatusCode))" -Level 'ERROR'
            $results.Failed++
            $results.Ports += [PSCustomObject]@{
                Access = "External"
                Status = "Unhealthy"
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "External access - Error: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        $results.Failed++
        $results.Ports += [PSCustomObject]@{
            Access = "External"
            Status = "Error"
        }
    }

    return $results
}

function Test-ProtectedEndpoints {
    Write-Log "=== Testing Protected Endpoints ===" -Level 'INFO'
    $results = @{
        Success = 0
        Failed = 0
        Endpoints = @()
    }

    $protectedEndpoints = @(
        @{Name = "Traefik Dashboard"; Url = "https://traefik.sharphorizons.tech" },
        @{Name = "Sonarr"; Url = "https://sonarr.sharphorizons.tech" },
        @{Name = "Radarr"; Url = "https://radarr.sharphorizons.tech" },
        @{Name = "Lidarr"; Url = "https://lidarr.sharphorizons.tech" },
        @{Name = "Readarr"; Url = "https://readarr.sharphorizons.tech" },
        @{Name = "Prowlarr"; Url = "https://prowlarr.sharphorizons.tech" },
        @{Name = "Bazarr"; Url = "https://bazarr.sharphorizons.tech" },
        @{Name = "qBittorrent"; Url = "https://qbit.sharphorizons.tech" }
    )

    foreach ($endpoint in $protectedEndpoints) {
        $success = Test-Endpoint -Name $endpoint.Name -Url $endpoint.Url -ExpectAuth
        if ($success) {
            $results.Success++
        }
        else {
            $results.Failed++
        }
        $results.Endpoints += [PSCustomObject]@{
            Name = $endpoint.Name
            Url = $endpoint.Url
            Protected = $success
        }
    }

    return $results
}

function Test-OAuth2Configuration {
    Write-Log "=== Testing OAuth2 Configuration ===" -Level 'INFO'
    $results = @{
        Success = 0
        Failed = 0
        Endpoints = @()
    }

    $baseUrl = "https://auth.sharphorizons.tech"
    $testUrls = @(
        "/oauth2/callback",
        "/oauth2/start",
        "/oauth2/sign_in",
        "/ping"
    )

    foreach ($path in $testUrls) {
        $url = $baseUrl + $path
        Write-Log "Testing endpoint: $url"
        try {
            $response = Invoke-WebRequest -Uri $url -Method GET -SkipCertificateCheck
            Write-Log "Status: $($response.StatusCode)" -Level 'SUCCESS'
            Write-Verbose "Headers: $($response.Headers | ConvertTo-Json)"
            $results.Success++
            $results.Endpoints += [PSCustomObject]@{
                Url = $url
                Status = $response.StatusCode
                Success = $true
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Error: $errorMessage" -Level 'ERROR'
            Write-Verbose "Exception details: $($_.Exception)"
            $results.Failed++
            $results.Endpoints += [PSCustomObject]@{
                Url = $url
                Status = $_.Exception.Response.StatusCode.value__
                Success = $false
            }
        }
    }

    return $results
}

function Main {
    try {
        Write-Log "Starting authentication tests..."
        Initialize-Environment

        # Test OAuth2 Proxy health
        $proxyResults = Test-OAuth2Proxy

        # Test protected endpoints
        $endpointResults = Test-ProtectedEndpoints

        # Test Plex authentication
        $plexSuccess = Test-Endpoint -Name "Plex" -Url "https://plex.sharphorizons.tech" -ExpectPlexAuth

        # Test OAuth2 configuration
        $configResults = Test-OAuth2Configuration

        # Generate summary
        Write-Log "`n=== Authentication Test Summary ===" -Level 'INFO'

        # OAuth2 Proxy summary
        Write-Log "OAuth2 Proxy Health:" -Level 'INFO'
        Write-Log "  Success: $($proxyResults.Success)" -Level $(if ($proxyResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($proxyResults.Failed)" -Level $(if ($proxyResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })

        # Protected endpoints summary
        Write-Log "Protected Endpoints:" -Level 'INFO'
        Write-Log "  Success: $($endpointResults.Success)" -Level $(if ($endpointResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($endpointResults.Failed)" -Level $(if ($endpointResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })

        # Plex authentication summary
        Write-Log "Plex Authentication:" -Level $(if ($plexSuccess) { 'SUCCESS' } else { 'ERROR' })

        # OAuth2 configuration summary
        Write-Log "OAuth2 Configuration:" -Level 'INFO'
        Write-Log "  Success: $($configResults.Success)" -Level $(if ($configResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($configResults.Failed)" -Level $(if ($configResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })

        # Overall status
        $allSuccess = (
            $proxyResults.Failed -eq 0 -and
            $endpointResults.Failed -eq 0 -and
            $plexSuccess -and
            $configResults.Failed -eq 0
        )

        if ($allSuccess) {
            Write-Log "`nAll authentication tests passed successfully!" -Level 'SUCCESS'
            exit 0
        }
        else {
            Write-Log "`nSome authentication tests failed. Check the log for details." -Level 'ERROR'
            exit 1
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Authentication testing failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main
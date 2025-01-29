<#
.SYNOPSIS
    Tests the health and connectivity of all services in the Plex environment.

.DESCRIPTION
    This script performs comprehensive testing of all services including:
    - Docker service status
    - Container health checks
    - Network connectivity
    - Traefik dashboard accessibility
    - Service endpoint validation
    The script includes detailed logging and status reporting for each test.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\service-test.log".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.DEPENDENCIES
    Required tools:
    - Docker
    - PowerShell 7.0 or later

.EXAMPLE
    .\test_services.ps1 -LogFile "D:\logs\service-test.log" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$LogFile = ".\logs\service-test.log",
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

    # Verify Docker is running
    try {
        $null = docker info
        Write-Log "Docker service is running" -Level 'SUCCESS'
    }
    catch {
        throw "Docker is not running or not accessible"
    }
}

function Test-ServiceHealth {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [string]$HealthEndpoint = ""
    )

    Write-Log "Testing $ServiceName..."
    try {
        # Check if container is running
        $container = docker ps --filter "name=^/${ContainerName}$" --format "{{.Status}}"
        if (-not $container) {
            Write-Log "$ServiceName - Container not running" -Level 'ERROR'
            return $false
        }

        if ($container -notmatch "^Up ") {
            Write-Log "$ServiceName - Container status: $container" -Level 'ERROR'
            return $false
        }

        # If health endpoint is provided, test it
        if ($HealthEndpoint) {
            $response = Invoke-WebRequest -Uri $HealthEndpoint -UseBasicParsing -SkipCertificateCheck
            if ($response.StatusCode -ne 200) {
                Write-Log "$ServiceName - Health check returned status $($response.StatusCode)" -Level 'ERROR'
                return $false
            }
        }

        Write-Log "$ServiceName - Service is healthy" -Level 'SUCCESS'
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "$ServiceName - Error: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-NetworkConnectivity {
    Write-Log "Testing internal network connectivity..."
    try {
        $network = docker network inspect proxy --format "{{range .Containers}}{{.Name}} {{end}}"
        if ($network) {
            Write-Log "Network connectivity OK" -Level 'SUCCESS'
            Write-Log "Connected containers: $network" -Level 'INFO'
            return $true
        }
        else {
            Write-Log "No containers connected to proxy network" -Level 'ERROR'
            return $false
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error inspecting network: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-TraefikDashboard {
    Write-Log "Testing Traefik Dashboard..."
    try {
        $response = Invoke-WebRequest -Uri "https://traefik.sharphorizons.tech" -UseBasicParsing -SkipCertificateCheck
        Write-Log "Traefik Dashboard is accessible" -Level 'SUCCESS'
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Cannot access Traefik Dashboard: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-AllServices {
    $results = @{
        Success = 0
        Failed = 0
        Services = @()
    }

    # Test core services
    $coreServices = @(
        @{Name = "Traefik"; Container = "traefik" },
        @{Name = "OAuth2 Proxy"; Container = "oauth2-proxy" }
    )

    foreach ($service in $coreServices) {
        $success = Test-ServiceHealth -ServiceName $service.Name -ContainerName $service.Container
        if ($success) {
            $results.Success++
        }
        else {
            $results.Failed++
        }
        $results.Services += [PSCustomObject]@{
            Name = $service.Name
            Type = "Core"
            Status = if ($success) { "Healthy" } else { "Unhealthy" }
        }
    }

    # Test media services
    $mediaServices = @(
        @{Name = "Plex"; Container = "plex" },
        @{Name = "Sonarr"; Container = "sonarr" },
        @{Name = "Radarr"; Container = "radarr" },
        @{Name = "Lidarr"; Container = "lidarr" },
        @{Name = "Readarr"; Container = "readarr" },
        @{Name = "Prowlarr"; Container = "prowlarr" },
        @{Name = "Bazarr"; Container = "bazarr" },
        @{Name = "qBittorrent"; Container = "qbittorrent" }
    )

    foreach ($service in $mediaServices) {
        $success = Test-ServiceHealth -ServiceName $service.Name -ContainerName $service.Container
        if ($success) {
            $results.Success++
        }
        else {
            $results.Failed++
        }
        $results.Services += [PSCustomObject]@{
            Name = $service.Name
            Type = "Media"
            Status = if ($success) { "Healthy" } else { "Unhealthy" }
        }
    }

    return $results
}

function Main {
    try {
        Write-Log "Starting services verification..."
        Initialize-Environment

        # Test all services
        $serviceResults = Test-AllServices

        # Test network connectivity
        $networkSuccess = Test-NetworkConnectivity

        # Test Traefik dashboard
        $dashboardSuccess = Test-TraefikDashboard

        # Generate summary
        Write-Log "`n=== Services Verification Summary ===" -Level 'INFO'

        # Services summary
        Write-Log "Service Health:" -Level 'INFO'
        Write-Log "  Success: $($serviceResults.Success)" -Level $(if ($serviceResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($serviceResults.Failed)" -Level $(if ($serviceResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })

        # Group services by type and status
        $serviceResults.Services | Group-Object Type | ForEach-Object {
            Write-Log "`n$($_.Name) Services:" -Level 'INFO'
            $_.Group | ForEach-Object {
                Write-Log "  - $($_.Name): $($_.Status)" -Level $(if ($_.Status -eq "Healthy") { 'SUCCESS' } else { 'ERROR' })
            }
        }

        # Network and dashboard summary
        Write-Log "`nNetwork Connectivity: $(if ($networkSuccess) { 'OK' } else { 'Failed' })" `
            -Level $(if ($networkSuccess) { 'SUCCESS' } else { 'ERROR' })
        Write-Log "Traefik Dashboard: $(if ($dashboardSuccess) { 'Accessible' } else { 'Inaccessible' })" `
            -Level $(if ($dashboardSuccess) { 'SUCCESS' } else { 'ERROR' })

        # Overall status
        $allSuccess = (
            $serviceResults.Failed -eq 0 -and
            $networkSuccess -and
            $dashboardSuccess
        )

        if ($allSuccess) {
            Write-Log "`nAll service tests passed successfully!" -Level 'SUCCESS'
            exit 0
        }
        else {
            Write-Log "`nSome service tests failed. Check the log for details." -Level 'ERROR'
            exit 1
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Service verification failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main
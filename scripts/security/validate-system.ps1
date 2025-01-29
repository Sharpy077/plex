<#
.SYNOPSIS
    Performs comprehensive system validation of the Plex server environment.

.DESCRIPTION
    This script performs a complete validation of the system including:
    - Docker service health checks
    - Network connectivity between services
    - Mount point validation
    - Traefik configuration verification
    - Secret file validation
    The script includes detailed logging and error reporting for each validation step.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\system-validation.log".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.DEPENDENCIES
    Required tools:
    - Docker
    - netcat (nc) in Docker containers
    - PowerShell 7.0 or later

.EXAMPLE
    .\validate-system.ps1 -LogFile "D:\logs\system-validation.log" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$LogFile = ".\logs\system-validation.log",
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
        Write-Log "Created log directory: $logDir"
    }

    # Verify Docker is running
    try {
        $null = docker info
        Write-Log "Docker is running" -Level 'SUCCESS'
    }
    catch {
        throw "Docker is not running or not accessible"
    }
}

function Test-DockerService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    try {
        $container = docker ps -q -f name=^/${ServiceName}$
        if (-not $container) {
            Write-Log "$ServiceName is not running" -Level 'ERROR'
            return $false
        }

        $status = docker inspect --format='{{.State.Status}}' $container
        $health = docker inspect --format='{{.State.Health.Status}}' $container 2>$null

        if ($status -eq "running") {
            if ($health -and $health -ne "healthy") {
                Write-Log "$ServiceName is running but health check shows: $health" -Level 'WARNING'
                return $false
            }
            Write-Log "$ServiceName is running properly" -Level 'SUCCESS'
            return $true
        }

        Write-Log "$ServiceName is not in running state: $status" -Level 'ERROR'
        return $false
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error checking $ServiceName: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-NetworkConnectivity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Container,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        $result = docker exec $Container timeout 5 nc -zv $Target $Port 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Network connectivity from $Container to $Target`:$Port successful" -Level 'SUCCESS'
            return $true
        }
        Write-Log "Network connectivity from $Container to $Target`:$Port failed" -Level 'ERROR'
        return $false
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error testing network connectivity from $Container to $Target`:$Port`: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-MountPoints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Container
    )

    try {
        $mounts = docker inspect --format='{{range .Mounts}}{{.Source}}:{{.Destination}}{{println}}{{end}}' $Container
        if (-not $mounts) {
            Write-Log "No mount points found for $Container" -Level 'WARNING'
            return $false
        }

        Write-Log "Mount points for $Container`:" -Level 'INFO'
        $allValid = $true

        $mounts | ForEach-Object {
            $source, $dest = $_.Split(":")
            if (Test-Path $source) {
                Write-Log "  $_ (Source exists)" -Level 'SUCCESS'
            }
            else {
                Write-Log "  $_ (Source missing)" -Level 'ERROR'
                $allValid = $false
            }
        }

        return $allValid
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error checking mount points for $Container`: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-TraefikConfig {
    try {
        # Check Traefik dynamic configuration
        if (-not (Test-Path "traefik/config")) {
            Write-Log "Traefik config directory missing" -Level 'ERROR'
            return $false
        }

        # Validate middleware configuration
        $middlewareConfig = Get-Content "traefik/config/middleware.yml" -Raw
        if ($middlewareConfig -notmatch "chain-secure") {
            Write-Log "Secure middleware chain not configured" -Level 'ERROR'
            return $false
        }

        Write-Log "Traefik configuration valid" -Level 'SUCCESS'
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error checking Traefik configuration: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-Secrets {
    try {
        $requiredSecrets = @(
            "github_client_id.secret",
            "github_client_secret.secret",
            "auth_secret.secret",
            "prowlarr_api_key.secret",
            "radarr_api_key.secret",
            "sonarr_api_key.secret",
            "lidarr_api_key.secret",
            "readarr_api_key.secret"
        )

        $allValid = $true
        foreach ($secret in $requiredSecrets) {
            $path = Join-Path "docker/secrets" $secret
            if (-not (Test-Path $path)) {
                Write-Log "Missing required secret: $secret" -Level 'ERROR'
                $allValid = $false
                continue
            }

            $content = Get-Content $path -Raw
            if ([string]::IsNullOrWhiteSpace($content)) {
                Write-Log "Empty secret file: $secret" -Level 'ERROR'
                $allValid = $false
            }
        }

        if ($allValid) {
            Write-Log "All required secrets present and populated" -Level 'SUCCESS'
        }
        return $allValid
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error checking secrets: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-SystemComponents {
    # Define services to check
    $services = @(
        "traefik", "plex", "sonarr", "radarr", "lidarr",
        "prowlarr", "bazarr", "readarr", "qbittorrent",
        "oauth2-proxy", "prometheus", "alertmanager"
    )

    # Define network connectivity tests
    $networkTests = @(
        @{ Container = "prowlarr"; Target = "qbittorrent"; Port = 8080 },
        @{ Container = "radarr"; Target = "qbittorrent"; Port = 8080 },
        @{ Container = "sonarr"; Target = "qbittorrent"; Port = 8080 },
        @{ Container = "lidarr"; Target = "qbittorrent"; Port = 8080 }
    )

    $results = @{
        Services = @()
        Network = @()
        Mounts = @()
        Traefik = $false
        Secrets = $false
    }

    # 1. Check all services
    Write-Log "=== Checking Services ===" -Level 'INFO'
    foreach ($service in $services) {
        $serviceValid = Test-DockerService $service
        $results.Services += [PSCustomObject]@{
            Service = $service
            Valid = $serviceValid
        }
    }

    # 2. Check network connectivity
    Write-Log "=== Checking Network Connectivity ===" -Level 'INFO'
    foreach ($test in $networkTests) {
        $networkValid = Test-NetworkConnectivity $test.Container $test.Target $test.Port
        $results.Network += [PSCustomObject]@{
            Source = $test.Container
            Target = "$($test.Target):$($test.Port)"
            Valid = $networkValid
        }
    }

    # 3. Check mount points
    Write-Log "=== Checking Mount Points ===" -Level 'INFO'
    foreach ($service in $services) {
        $mountsValid = Test-MountPoints $service
        $results.Mounts += [PSCustomObject]@{
            Service = $service
            Valid = $mountsValid
        }
    }

    # 4. Check Traefik configuration
    Write-Log "=== Checking Traefik Configuration ===" -Level 'INFO'
    $results.Traefik = Test-TraefikConfig

    # 5. Check secrets
    Write-Log "=== Checking Secrets ===" -Level 'INFO'
    $results.Secrets = Test-Secrets

    return $results
}

function Main {
    try {
        Write-Log "Starting system validation..."
        Initialize-Environment

        $results = Test-SystemComponents

        # Generate summary
        Write-Log "`n=== Validation Summary ===" -Level 'INFO'

        # Services summary
        $failedServices = $results.Services | Where-Object { -not $_.Valid }
        if ($failedServices) {
            Write-Log "Failed Services:" -Level 'ERROR'
            $failedServices | ForEach-Object {
                Write-Log "  - $($_.Service)" -Level 'ERROR'
            }
        }

        # Network summary
        $failedConnections = $results.Network | Where-Object { -not $_.Valid }
        if ($failedConnections) {
            Write-Log "Failed Network Connections:" -Level 'ERROR'
            $failedConnections | ForEach-Object {
                Write-Log "  - $($_.Source) -> $($_.Target)" -Level 'ERROR'
            }
        }

        # Mounts summary
        $failedMounts = $results.Mounts | Where-Object { -not $_.Valid }
        if ($failedMounts) {
            Write-Log "Failed Mount Points:" -Level 'ERROR'
            $failedMounts | ForEach-Object {
                Write-Log "  - $($_.Service)" -Level 'ERROR'
            }
        }

        # Traefik and Secrets summary
        Write-Log "Traefik Configuration: $(if ($results.Traefik) { 'Valid' } else { 'Invalid' })" `
            -Level $(if ($results.Traefik) { 'SUCCESS' } else { 'ERROR' })
        Write-Log "Secrets Configuration: $(if ($results.Secrets) { 'Valid' } else { 'Invalid' })" `
            -Level $(if ($results.Secrets) { 'SUCCESS' } else { 'ERROR' })

        # Overall status
        $systemValid = (
            ($results.Services | Where-Object { -not $_.Valid }).Count -eq 0 -and
            ($results.Network | Where-Object { -not $_.Valid }).Count -eq 0 -and
            ($results.Mounts | Where-Object { -not $_.Valid }).Count -eq 0 -and
            $results.Traefik -and
            $results.Secrets
        )

        if ($systemValid) {
            Write-Log "System validation completed successfully!" -Level 'SUCCESS'
            exit 0
        }
        else {
            Write-Log "System validation failed. Check the log for details." -Level 'ERROR'
            exit 1
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "System validation failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main
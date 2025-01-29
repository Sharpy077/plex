<#
.SYNOPSIS
    Tests and verifies the setup requirements for the Plex environment.

.DESCRIPTION
    This script performs comprehensive verification of the setup including:
    - Docker network configuration
    - Required directory structure
    - Configuration files presence
    - Environment variables validation
    - Docker Compose configuration
    The script includes detailed logging and can automatically fix some issues.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\setup-test.log".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.PARAMETER AutoFix
    Automatically attempt to fix issues when possible. Defaults to $true.

.DEPENDENCIES
    Required tools:
    - Docker
    - Docker Compose
    - PowerShell 7.0 or later

.EXAMPLE
    .\test_setup.ps1 -LogFile "D:\logs\setup-test.log" -VerboseLogging $true -AutoFix $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$LogFile = ".\logs\setup-test.log",
    [bool]$VerboseLogging = $true,
    [bool]$AutoFix = $true
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
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'FIX')]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"

    # Write to console with color
    $color = switch ($Level) {
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        'FIX' { 'Cyan' }
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

function Test-DockerNetwork {
    Write-Log "Testing Docker network 'proxy'..."
    try {
        # First check if Docker is running
        try {
            $null = docker info 2>$null
        }
        catch {
            Write-Log "Docker is not running" -Level 'ERROR'
            return $false
        }

        $network = docker network inspect proxy 2>$null
        if (-not $network) {
            throw "Network not found"
        }

        $networkInfo = $network | ConvertFrom-Json

        # Validate network configuration
        if ($networkInfo.Driver -ne "bridge") {
            Write-Log "Warning: Network driver is not 'bridge'" -Level 'WARNING'
        }

        if (-not $networkInfo.IPAM.Config) {
            Write-Log "Warning: Network has no IPAM configuration" -Level 'WARNING'
        }

        # Check connected containers
        $containers = $networkInfo.Containers
        if ($containers.PSObject.Properties.Count -gt 0) {
            Write-Log "Connected containers: $($containers.PSObject.Properties.Count)" -Level 'SUCCESS'
            foreach ($container in $containers.PSObject.Properties) {
                $containerInfo = $container.Value
                $containerName = $containerInfo.Name
                $status = docker ps --filter ('name=^/{0}$' -f $containerName) --format "{{.Status}}"
                $healthStatus = if ($status -match "healthy") { "healthy" } elseif ($status -match "unhealthy") { "unhealthy" } else { "unknown" }

                Write-Log "  - $containerName" -Level 'INFO'
                Write-Log "    IP: $($containerInfo.IPv4Address)" -Level 'INFO'
                Write-Log "    MAC: $($containerInfo.MacAddress)" -Level 'INFO'
                Write-Log "    Health: $healthStatus" -Level $(if ($healthStatus -eq "healthy") { 'SUCCESS' } elseif ($healthStatus -eq "unhealthy") { 'ERROR' } else { 'WARNING' })
            }
        }
        else {
            Write-Log "No containers connected to the network" -Level 'WARNING'
        }

        Write-Log "Docker network 'proxy' exists and is properly configured" -Level 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Docker network 'proxy' not found" -Level 'ERROR'
        if ($AutoFix) {
            try {
                # Create network with specific configuration
                $networkCreate = docker network create `
                    --driver bridge `
                    --subnet 172.20.0.0/16 `
                    --gateway 172.20.0.1 `
                    proxy 2>&1

                Write-Log "Created Docker network 'proxy' with custom configuration" -Level 'FIX'
                Write-Log "Network ID: $networkCreate" -Level 'INFO'
                return $true
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Failed to create network: $errorMessage" -Level 'ERROR'
                Write-Verbose "Exception details: $($_.Exception)"
                return $false
            }
        }
        return $false
    }
}

function Test-RequiredDirectories {
    Write-Log "Checking required directories..."
    $results = @{
        Success = 0
        Failed = 0
        Missing = @()
    }

    $directories = @(
        "docker\secrets",
        "config\plex",
        "config\qbittorrent",
        "config\prowlarr",
        "config\radarr",
        "config\sonarr",
        "config\lidarr",
        "config\readarr",
        "config\bazarr",
        "tv",
        "movies",
        "music",
        "downloads",
        "traefik\config",
        "letsencrypt"
    )

    foreach ($dir in $directories) {
        if (Test-Path $dir -PathType Container) {
            Write-Log "Directory exists: $dir" -Level 'SUCCESS'
            $results.Success++
        }
        else {
            Write-Log "Missing directory: $dir" -Level 'ERROR'
            $results.Failed++
            $results.Missing += $dir

            if ($AutoFix) {
                try {
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                    Write-Log "Created directory: $dir" -Level 'FIX'
                    $results.Failed--
                    $results.Success++
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    Write-Log "Failed to create directory $dir: $errorMessage" -Level 'ERROR'
                    Write-Verbose "Exception details: $($_.Exception)"
                }
            }
        }
    }

    return $results
}

function Test-ConfigurationFiles {
    Write-Log "Checking configuration files..."
    $results = @{
        Success = 0
        Failed = 0
        Missing = @()
    }

    $files = @(
        "traefik\config\middlewares.yml",
        ".env"
    )

    foreach ($file in $files) {
        if (Test-Path $file -PathType Leaf) {
            Write-Log "File exists: $file" -Level 'SUCCESS'
            $results.Success++
        }
        else {
            Write-Log "Missing file: $file" -Level 'ERROR'
            $results.Failed++
            $results.Missing += $file
        }
    }

    return $results
}

function Test-EnvironmentVariables {
    Write-Log "Checking environment variables..."
    $results = @{
        Success = 0
        Failed = 0
        Missing = @()
    }

    if (-not (Test-Path ".env" -PathType Leaf)) {
        Write-Log ".env file not found" -Level 'ERROR'
        return $results
    }

    $requiredVars = @(
        "COOKIE_SECRET",
        "GITHUB_CLIENT_ID",
        "GITHUB_CLIENT_SECRET",
        "TZ",
        "PUID",
        "PGID"
    )

    # Read file content once to improve performance
    try {
        $envContent = Get-Content -Path ".env" -Raw
        foreach ($var in $requiredVars) {
            # Using [regex] to properly escape the variable name
            $pattern = [regex]::Escape($var) + '=.+'
            if ($envContent -match $pattern) {
                Write-Log "Environment variable exists: $var" -Level 'SUCCESS'
                $results.Success++
            }
            else {
                Write-Log "Missing environment variable: $var" -Level 'ERROR'
                $results.Failed++
                $results.Missing += $var
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error reading .env file: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $results
    }

    # Validate variable values
    if ($results.Success -gt 0) {
        Write-Log "Validating environment variable values..." -Level 'INFO'
        try {
            $envConfig = @{}
            $envContent -split "`n" | ForEach-Object {
                if ($_ -match '^([^=]+)=(.*)$') {
                    $envConfig[$Matches[1]] = $Matches[2].Trim()
                }
            }

            # Validate PUID and PGID are numbers
            if ($envConfig.ContainsKey('PUID') -and -not ($envConfig['PUID'] -match '^\d+$')) {
                Write-Log "PUID must be a number" -Level 'ERROR'
                $results.Failed++
            }
            if ($envConfig.ContainsKey('PGID') -and -not ($envConfig['PGID'] -match '^\d+$')) {
                Write-Log "PGID must be a number" -Level 'ERROR'
                $results.Failed++
            }

            # Validate TZ is a valid timezone
            if ($envConfig.ContainsKey('TZ')) {
                try {
                    [System.TimeZoneInfo]::FindSystemTimeZoneById($envConfig['TZ'])
                }
                catch {
                    Write-Log "Invalid timezone format: $($envConfig['TZ'])" -Level 'ERROR'
                    $results.Failed++
                }
            }

            # Validate secrets have minimum length
            $minSecretLength = 16
            if ($envConfig.ContainsKey('COOKIE_SECRET') -and $envConfig['COOKIE_SECRET'].Length -lt $minSecretLength) {
                Write-Log "COOKIE_SECRET should be at least $minSecretLength characters" -Level 'WARNING'
            }
            if ($envConfig.ContainsKey('GITHUB_CLIENT_SECRET') -and $envConfig['GITHUB_CLIENT_SECRET'].Length -lt $minSecretLength) {
                Write-Log "GITHUB_CLIENT_SECRET should be at least $minSecretLength characters" -Level 'WARNING'
            }

            # Validate GitHub Client ID format
            if ($envConfig.ContainsKey('GITHUB_CLIENT_ID') -and -not ($envConfig['GITHUB_CLIENT_ID'] -match '^[0-9a-fA-F]{20}$')) {
                Write-Log "GITHUB_CLIENT_ID should be a 20-character hexadecimal string" -Level 'WARNING'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Error validating environment variables: $errorMessage" -Level 'ERROR'
            Write-Verbose "Exception details: $($_.Exception)"
        }
    }

    return $results
}

function Test-DockerCompose {
    Write-Log "Validating docker-compose.yml..."
    try {
        # First check if docker-compose is installed
        try {
            $version = docker-compose version --short 2>$null
            Write-Log "Docker Compose version: $version" -Level 'INFO'
        }
        catch {
            Write-Log "Docker Compose is not installed" -Level 'ERROR'
            return $false
        }

        # Validate configuration
        $output = docker-compose config 2>&1
        $config = $output | docker-compose config -q 2>&1

        # Parse and validate services
        $services = ($output | Select-String -Pattern "^  \w+:").Matches.Value

        if ($services) {
            Write-Log "Defined services:" -Level 'INFO'
            foreach ($service in $services) {
                $serviceName = $service.Trim(':')
                Write-Log "  - $serviceName" -Level 'INFO'

                # Check service configuration
                $serviceConfig = $config | Select-String -Pattern "^${serviceName}:" -Context 0,10
                if ($serviceConfig) {
                    # Validate image specification
                    if (-not ($serviceConfig -match 'image:')) {
                        Write-Log "    Warning: No image specified for $serviceName" -Level 'WARNING'
                    }

                    # Check for container name
                    if (-not ($serviceConfig -match 'container_name:')) {
                        Write-Log "    Warning: No container_name specified for $serviceName" -Level 'WARNING'
                    }

                    # Check for restart policy
                    if (-not ($serviceConfig -match 'restart:')) {
                        Write-Log "    Warning: No restart policy specified for $serviceName" -Level 'WARNING'
                    }
                }
            }
        }
        else {
            Write-Log "Warning: No services defined in docker-compose.yml" -Level 'WARNING'
        }

        Write-Log "docker-compose.yml is valid" -Level 'SUCCESS'
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Invalid docker-compose.yml: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"

        # Enhanced error analysis
        if ($errorMessage -match "version") {
            Write-Log "Hint: Check if docker-compose version is specified correctly" -Level 'WARNING'
            Write-Log "Supported versions: 2.x, 3.x" -Level 'INFO'
        }
        elseif ($errorMessage -match "service") {
            Write-Log "Hint: Verify service definitions and indentation" -Level 'WARNING'
            Write-Log "Common issues:" -Level 'INFO'
            Write-Log "- Incorrect indentation" -Level 'INFO'
            Write-Log "- Missing required fields" -Level 'INFO'
            Write-Log "- Invalid service names" -Level 'INFO'
        }
        elseif ($errorMessage -match "volume") {
            Write-Log "Hint: Check volume mappings and paths" -Level 'WARNING'
            Write-Log "Common issues:" -Level 'INFO'
            Write-Log "- Invalid path format" -Level 'INFO'
            Write-Log "- Missing volume definitions" -Level 'INFO'
            Write-Log "- Incorrect mount specifications" -Level 'INFO'
        }

        return $false
    }
}

function Test-ServiceHealth {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [string]$HealthEndpoint = "",
        [int]$RetryCount = 3,
        [int]$RetryDelay = 5
    )

    Write-Log "Testing $ServiceName..."
    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            # Check if container is running
            $container = docker ps --filter "name=^/${ContainerName}$" --format "{{.Status}}"
            if (-not $container) {
                if ($i -lt $RetryCount) {
                    Write-Log "$ServiceName - Container not running (Attempt $i of $RetryCount)" -Level 'WARNING'
                    Start-Sleep -Seconds $RetryDelay
                    continue
                }
                Write-Log "$ServiceName - Container not running" -Level 'ERROR'
                return $false
            }

            if ($container -notmatch "^Up ") {
                if ($i -lt $RetryCount) {
                    Write-Log "$ServiceName - Container status: $container (Attempt $i of $RetryCount)" -Level 'WARNING'
                    Start-Sleep -Seconds $RetryDelay
                    continue
                }
                Write-Log "$ServiceName - Container status: $container" -Level 'ERROR'
                return $false
            }

            # If health endpoint is provided, test it
            if ($HealthEndpoint) {
                $response = Invoke-WebRequest -Uri $HealthEndpoint -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
                if ($response.StatusCode -ne 200) {
                    if ($i -lt $RetryCount) {
                        Write-Log "$ServiceName - Health check returned status $($response.StatusCode) (Attempt $i of $RetryCount)" -Level 'WARNING'
                        Start-Sleep -Seconds $RetryDelay
                        continue
                    }
                    Write-Log "$ServiceName - Health check returned status $($response.StatusCode)" -Level 'ERROR'
                    return $false
                }
            }

            Write-Log "$ServiceName - Service is healthy" -Level 'SUCCESS'
            return $true
        }
        catch {
            if ($i -lt $RetryCount) {
                $errorMessage = $_.Exception.Message
                Write-Log "$ServiceName - Error: $errorMessage (Attempt $i of $RetryCount)" -Level 'WARNING'
                Write-Verbose "Exception details: $($_.Exception)"
                Start-Sleep -Seconds $RetryDelay
                continue
            }
            $errorMessage = $_.Exception.Message
            Write-Log "$ServiceName - Error: $errorMessage" -Level 'ERROR'
            Write-Verbose "Exception details: $($_.Exception)"
            return $false
        }
    }
}

function Main {
    try {
        Write-Log "Starting setup verification..."
        Initialize-Environment

        # Test Docker network
        $networkSuccess = Test-DockerNetwork

        # Test required directories
        $dirResults = Test-RequiredDirectories

        # Test configuration files
        $configResults = Test-ConfigurationFiles

        # Test environment variables
        $envResults = Test-EnvironmentVariables

        # Test Docker Compose
        $composeSuccess = Test-DockerCompose

        # Generate summary
        Write-Log "`n=== Setup Verification Summary ===" -Level 'INFO'

        # Docker network status
        Write-Log "Docker Network:" -Level $(if ($networkSuccess) { 'SUCCESS' } else { 'ERROR' })
        Write-Log "  - Proxy network: $(if ($networkSuccess) { 'OK' } else { 'Failed' })"

        # Directory status
        Write-Log "`nDirectories:" -Level 'INFO'
        Write-Log "  Success: $($dirResults.Success)" -Level $(if ($dirResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($dirResults.Failed)" -Level $(if ($dirResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })
        if ($dirResults.Missing.Count -gt 0) {
            Write-Log "  Missing directories:" -Level 'WARNING'
            $dirResults.Missing | ForEach-Object { Write-Log "    - $_" -Level 'WARNING' }
        }

        # Configuration files status
        Write-Log "`nConfiguration Files:" -Level 'INFO'
        Write-Log "  Success: $($configResults.Success)" -Level $(if ($configResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($configResults.Failed)" -Level $(if ($configResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })
        if ($configResults.Missing.Count -gt 0) {
            Write-Log "  Missing files:" -Level 'WARNING'
            $configResults.Missing | ForEach-Object { Write-Log "    - $_" -Level 'WARNING' }
        }

        # Environment variables status
        Write-Log "`nEnvironment Variables:" -Level 'INFO'
        Write-Log "  Success: $($envResults.Success)" -Level $(if ($envResults.Failed -eq 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "  Failed: $($envResults.Failed)" -Level $(if ($envResults.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })
        if ($envResults.Missing.Count -gt 0) {
            Write-Log "  Missing variables:" -Level 'WARNING'
            $envResults.Missing | ForEach-Object { Write-Log "    - $_" -Level 'WARNING' }
        }

        # Docker Compose status
        Write-Log "`nDocker Compose:" -Level $(if ($composeSuccess) { 'SUCCESS' } else { 'ERROR' })
        Write-Log "  - Configuration: $(if ($composeSuccess) { 'Valid' } else { 'Invalid' })"

        # Overall status
        $allSuccess = (
            $networkSuccess -and
            $dirResults.Failed -eq 0 -and
            $configResults.Failed -eq 0 -and
            $envResults.Failed -eq 0 -and
            $composeSuccess
        )

        if ($allSuccess) {
            Write-Log "`nAll setup verification tests passed successfully!" -Level 'SUCCESS'
            exit 0
        }
        else {
            Write-Log "`nSome setup verification tests failed. Check the log for details." -Level 'ERROR'
            exit 1
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Setup verification failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main
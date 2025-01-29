<#
.SYNOPSIS
    Retrieves API keys from running services and stores them in secret files.

.DESCRIPTION
    This script retrieves API keys from the configuration files of running services including:
    - Prowlarr
    - Radarr
    - Sonarr
    - Lidarr
    - Readarr
    The keys are stored in individual secret files for secure access by other scripts.

.PARAMETER SecretsDir
    Directory to store the API key secret files. Defaults to "./docker/secrets".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.DEPENDENCIES
    Required tools:
    - Docker
    - PowerShell 7.0 or later

.EXAMPLE
    .\get-api-keys.ps1 -SecretsDir "D:\secrets" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$SecretsDir = "./docker/secrets",
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
    Write-Verbose "Logged: $logMessage"
}

function Initialize-Environment {
    try {
        # Verify Docker is running
        $null = docker info
        Write-Log "Docker is running" -Level 'SUCCESS'

        # Create secrets directory if it doesn't exist
        if (-not (Test-Path $SecretsDir)) {
            New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null
            Write-Log "Created secrets directory: $SecretsDir" -Level 'SUCCESS'
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to initialize environment: $errorMessage" -Level 'ERROR'
        throw
    }
}

function Get-ServiceApiKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Container,
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    try {
        Write-Log "Getting API key for $ServiceName..."

        # Get the config file content
        $configContent = docker exec $Container cat $ConfigPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$ServiceName config file not found or not accessible" -Level 'WARNING'
            return $null
        }

        # Look for ApiKey in the XML content
        if ($configContent -match '<ApiKey>([^<]+)</ApiKey>') {
            $apiKey = $matches[1].Trim()
            if ($apiKey) {
                Write-Log "$ServiceName API key found" -Level 'SUCCESS'
                return $apiKey
            }
        }

        Write-Log "$ServiceName API key not found in config" -Level 'WARNING'
        return $null
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error getting $ServiceName API key: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        return $null
    }
}

function Update-ApiKeys {
    # Service configurations
    $services = @(
        @{
            Name = "Prowlarr"
            Container = "prowlarr"
            ConfigPath = "/config/config.xml"
            SecretFile = "prowlarr_api_key.secret"
        },
        @{
            Name = "Radarr"
            Container = "radarr"
            ConfigPath = "/config/config.xml"
            SecretFile = "radarr_api_key.secret"
        },
        @{
            Name = "Sonarr"
            Container = "sonarr"
            ConfigPath = "/config/config.xml"
            SecretFile = "sonarr_api_key.secret"
        },
        @{
            Name = "Lidarr"
            Container = "lidarr"
            ConfigPath = "/config/config.xml"
            SecretFile = "lidarr_api_key.secret"
        },
        @{
            Name = "Readarr"
            Container = "readarr"
            ConfigPath = "/config/config.xml"
            SecretFile = "readarr_api_key.secret"
        }
    )

    $results = @{
        Updated = 0
        Failed = 0
        Services = @()
    }

    foreach ($service in $services) {
        Write-Log "Processing $($service.Name)..." -Level 'INFO'
        $apiKey = Get-ServiceApiKey -Container $service.Container `
            -ServiceName $service.Name `
            -ConfigPath $service.ConfigPath

        if ($apiKey) {
            try {
                $secretPath = Join-Path $SecretsDir $service.SecretFile
                Set-Content -Path $secretPath -Value $apiKey -NoNewline
                Write-Log "Updated $($service.Name) API key in $($service.SecretFile)" -Level 'SUCCESS'
                $results.Updated++
                $results.Services += [PSCustomObject]@{
                    Service = $service.Name
                    Status = "Updated"
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Failed to save $($service.Name) API key: $errorMessage" -Level 'ERROR'
                Write-Verbose "Exception details: $($_.Exception)"
                $results.Failed++
                $results.Services += [PSCustomObject]@{
                    Service = $service.Name
                    Status = "Failed"
                }
            }
        }
        else {
            $results.Failed++
            $results.Services += [PSCustomObject]@{
                Service = $service.Name
                Status = "Not Found"
            }
        }
    }

    return $results
}

function Main {
    try {
        Write-Log "Starting API key retrieval..."
        Initialize-Environment

        $results = Update-ApiKeys

        # Generate summary
        Write-Log "`n=== API Key Retrieval Summary ===" -Level 'INFO'
        Write-Log "Updated Keys: $($results.Updated)" -Level $(if ($results.Updated -gt 0) { 'SUCCESS' } else { 'WARNING' })
        Write-Log "Failed Keys: $($results.Failed)" -Level $(if ($results.Failed -gt 0) { 'ERROR' } else { 'SUCCESS' })

        Write-Log "`nService Status:" -Level 'INFO'
        foreach ($service in $results.Services) {
            $level = switch ($service.Status) {
                "Updated" { 'SUCCESS' }
                "Failed" { 'ERROR' }
                default { 'WARNING' }
            }
            Write-Log "  - $($service.Service): $($service.Status)" -Level $level
        }

        if ($results.Failed -eq 0) {
            Write-Log "`nAPI key retrieval completed successfully!" -Level 'SUCCESS'
            exit 0
        }
        else {
            Write-Log "`nAPI key retrieval completed with errors. Check the log for details." -Level 'WARNING'
            exit 1
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "API key retrieval failed: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main
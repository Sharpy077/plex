# Rolling Update Manager
# Handles rolling updates of services with health checks and rollback capability

param (
    [Parameter(Mandatory = $true)]
    [string]$ServiceName,
    [string]$NewVersion,
    [int]$HealthCheckRetries = 3,
    [int]$HealthCheckDelay = 30,
    [switch]$ForceUpdate,
    [string]$LogPath = "../logs/deployment"
)

# Import common functions
. "../common/logging.ps1"
. "../common/config-helper.ps1"

# Initialize logging
$LogFile = Join-Path $LogPath "rolling-update-$(Get-Date -Format 'yyyyMMdd').log"
Initialize-Logging $LogFile

# Configuration
$config = @{
    HealthCheckEndpoint = "http://localhost:{0}/health"
    BackupPath          = "../backups/configs"
    ComposeFile         = "../docker-compose.yml"
}

function Backup-ServiceConfig {
    param (
        [string]$ServiceName
    )
    Write-Log "Backing up configuration for $ServiceName..."
    try {
        $backupDir = Join-Path $config.BackupPath "$ServiceName-$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        # Backup service configuration
        Copy-Item "../config/$ServiceName" $backupDir -Recurse -Force
        # Backup environment variables
        Copy-Item "../.env" "$backupDir/.env.backup" -Force

        Write-Log "Configuration backed up to $backupDir"
        return $backupDir
    }
    catch {
        Write-Log "Error backing up configuration: $_" -Level Error
        throw
    }
}

function Test-ServiceHealth {
    param (
        [string]$ServiceName,
        [int]$Port
    )
    Write-Log "Testing health of $ServiceName..."
    $healthUrl = $config.HealthCheckEndpoint -f $Port

    for ($i = 1; $i -le $HealthCheckRetries; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Log "Health check passed for $ServiceName"
                return $true
            }
        }
        catch {
            Write-Log "Health check attempt $i failed: $_" -Level Warning
        }
        Start-Sleep -Seconds $HealthCheckDelay
    }

    Write-Log "Health check failed for $ServiceName after $HealthCheckRetries attempts" -Level Error
    return $false
}

function Update-ServiceVersion {
    param (
        [string]$ServiceName,
        [string]$Version
    )
    Write-Log "Updating $ServiceName to version $Version..."
    try {
        # Update version in compose file
        $compose = Get-Content $config.ComposeFile -Raw | ConvertFrom-Yaml
        $compose.services.${ServiceName}.image = "${ServiceName}:${Version}"
        $compose | ConvertTo-Yaml | Set-Content $config.ComposeFile

        # Pull new image
        docker-compose pull $ServiceName

        Write-Log "Service version updated successfully"
        return $true
    }
    catch {
        Write-Log "Error updating service version: $_" -Level Error
        return $false
    }
}

function Start-RollingUpdate {
    param (
        [string]$ServiceName,
        [string]$Version,
        [string]$BackupPath
    )
    Write-Log "Starting rolling update for $ServiceName to version $Version..."
    try {
        # Stop service
        docker-compose stop $ServiceName

        # Update service version
        if (-not (Update-ServiceVersion -ServiceName $ServiceName -Version $Version)) {
            throw "Failed to update service version"
        }

        # Start service
        docker-compose up -d $ServiceName

        # Wait for service to be healthy
        Start-Sleep -Seconds $HealthCheckDelay
        $port = Get-ServicePort -ServiceName $ServiceName
        if (-not (Test-ServiceHealth -ServiceName $ServiceName -Port $port)) {
            throw "Service health check failed after update"
        }

        Write-Log "Rolling update completed successfully"
        return $true
    }
    catch {
        Write-Log "Error during rolling update: $_" -Level Error
        if (-not $ForceUpdate) {
            Write-Log "Rolling back to previous version..."
            Restore-ServiceConfig -BackupPath $BackupPath
            docker-compose up -d $ServiceName
        }
        return $false
    }
}

function Get-ServicePort {
    param (
        [string]$ServiceName
    )
    # Get service port from compose file
    $compose = Get-Content $config.ComposeFile -Raw | ConvertFrom-Yaml
    $ports = $compose.services.$ServiceName.ports
    if ($ports) {
        $portMapping = $ports[0] -split ':'
        return $portMapping[0]
    }
    throw "Could not determine service port"
}

function Restore-ServiceConfig {
    param (
        [string]$BackupPath
    )
    Write-Log "Restoring configuration from $BackupPath..."
    try {
        Copy-Item "$BackupPath/*" "../config/" -Recurse -Force
        Copy-Item "$BackupPath/.env.backup" "../.env" -Force
        Write-Log "Configuration restored successfully"
        return $true
    }
    catch {
        Write-Log "Error restoring configuration: $_" -Level Error
        return $false
    }
}

# Main execution
try {
    Write-Log "Starting rolling update process for $ServiceName..."

    # Validate service exists
    if (-not (docker-compose ps $ServiceName)) {
        throw "Service $ServiceName not found"
    }

    # Backup current configuration
    $backupPath = Backup-ServiceConfig -ServiceName $ServiceName

    # Perform rolling update
    $success = Start-RollingUpdate -ServiceName $ServiceName -Version $NewVersion -BackupPath $backupPath

    if ($success) {
        Write-Log "Rolling update completed successfully"
    }
    else {
        Write-Log "Rolling update failed" -Level Error
        exit 1
    }
}
catch {
    Write-Log "Critical error during update process: $_" -Level Error
    exit 1
}
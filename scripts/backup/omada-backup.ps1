<#
.SYNOPSIS
    Performs backup of Omada Controller configuration and related settings.

.DESCRIPTION
    This script performs a comprehensive backup of the Omada Controller environment including:
    - Omada Controller configuration files
    - VLAN configuration
    - Firewall rules
    - SSL configuration
    The script includes backup rotation and compression of all backed up files.

.PARAMETER RetentionDays
    Number of days to keep backups. Defaults to 7 days.

.PARAMETER BackupRoot
    Root directory for storing backups. Defaults to ".\omada_backups".

.PARAMETER OmadaConfigDir
    Directory containing Omada Controller configuration files.
    Defaults to "C:\Program Files\TP-Link\OmadaController\data".

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\omada-backup.ps1 -RetentionDays 14 -BackupRoot "D:\backups\omada"

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param (
    [int]$RetentionDays = 7,
    [string]$BackupRoot = ".\omada_backups",
    [string]$OmadaConfigDir = "C:\Program Files\TP-Link\OmadaController\data"
)

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function definitions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(
        switch ($Level) {
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'White' }
        }
    )
}

function Initialize-Environment {
    $script:BackupDate = Get-Date -Format "yyyy-MM-dd"
    $script:CurrentBackupDir = Join-Path $BackupRoot $script:BackupDate
    $script:BackupArchive = "omada_backup_$($script:BackupDate).zip"

    # Verify Omada config directory exists
    if (-not (Test-Path $OmadaConfigDir)) {
        throw "Omada configuration directory not found: $OmadaConfigDir"
    }

    # Create backup directory
    if (-not (Test-Path $script:CurrentBackupDir)) {
        New-Item -ItemType Directory -Force -Path $script:CurrentBackupDir | Out-Null
        Write-Log "Created backup directory: $($script:CurrentBackupDir)"
    }
}

function Backup-OmadaConfig {
    try {
        # Backup Omada Configuration
        Copy-Item -Path "$OmadaConfigDir\*" -Destination $script:CurrentBackupDir -Recurse -Force
        Write-Log "Backed up Omada configuration files"

        # Backup VLAN Configuration
        if (Test-Path ".\omada-vlan-config.txt") {
            Copy-Item ".\omada-vlan-config.txt" -Destination "$($script:CurrentBackupDir)\vlan_config_backup.txt"
            Write-Log "Backed up VLAN configuration"
        }
        else {
            Write-Log "VLAN configuration file not found" -Level 'WARNING'
        }

        # Backup Firewall Rules
        if (Test-Path ".\omada-firewall-rules.txt") {
            Copy-Item ".\omada-firewall-rules.txt" -Destination "$($script:CurrentBackupDir)\firewall_rules_backup.txt"
            Write-Log "Backed up firewall rules"
        }
        else {
            Write-Log "Firewall rules file not found" -Level 'WARNING'
        }

        # Backup SSL Configuration
        if (Test-Path ".\ssl-config.txt") {
            Copy-Item ".\ssl-config.txt" -Destination "$($script:CurrentBackupDir)\ssl_config_backup.txt"
            Write-Log "Backed up SSL configuration"
        }
        else {
            Write-Log "SSL configuration file not found" -Level 'WARNING'
        }

        # Compress backup
        Compress-Archive -Path "$($script:CurrentBackupDir)\*" -DestinationPath "$($script:CurrentBackupDir)\$($script:BackupArchive)" -Force
        Write-Log "Created backup archive: $($script:BackupArchive)"
    }
    catch {
        Write-Log "Failed to backup Omada configuration: $_" -Level 'ERROR'
        throw
    }
}

function Remove-OldBackups {
    Get-ChildItem $BackupRoot -Directory | Where-Object {
        $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Write-Log "Cleaned up old backup: $($_.Name)"
    }
}

function Get-BackupSize {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $size = (Get-ChildItem $BackupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
    return [math]::Round($size, 2)
}

function Main {
    try {
        Write-Log "Starting Omada backup process..."
        Initialize-Environment
        Backup-OmadaConfig
        Remove-OldBackups

        $backupSize = Get-BackupSize -BackupPath $script:CurrentBackupDir
        Write-Log "Backup completed successfully. Total size: $backupSize MB"
        Write-Log "Backup location: $($script:CurrentBackupDir)\$($script:BackupArchive)"
    }
    catch {
        Write-Log "Backup process failed: $_" -Level 'ERROR'
        throw
    }
}

# Script execution
Main

# Optional: Upload to remote storage
# Add your remote storage upload commands here
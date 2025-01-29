<#
.SYNOPSIS
    Performs comprehensive backup of all service configurations with integrity verification.

.DESCRIPTION
    This script performs a complete backup of the Plex server environment including:
    - Docker compose configuration
    - Service configurations (Radarr, Sonarr, etc.)
    - Compression of backups
    - Integrity verification of backups
    - Backup rotation based on retention policy
    - Email notifications of backup status
    The script includes SHA256 hash verification of all backed up files.

.PARAMETER RetentionDays
    Number of days to keep backups. Defaults to 7 days.

.PARAMETER BackupRoot
    Root directory for storing backups. Defaults to ".\backups".

.PARAMETER LogFile
    Path to the log file. Defaults to ".\backups\backup.log".

.ENVIRONMENT
    Required environment variables:
    - FROM_ADDRESS: Email address to send notifications from
    - ADMIN_EMAIL: Email address to send notifications to
    - SMTP_HOST: SMTP server hostname
    - SMTP_PORT: SMTP server port
    - SMTP_USERNAME: SMTP authentication username
    - SMTP_PASSWORD: SMTP authentication password

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\backup-script.ps1 -RetentionDays 14 -BackupRoot "D:\backups" -LogFile "D:\logs\backup.log"

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param (
    [int]$RetentionDays = 7,
    [string]$BackupRoot = ".\backups",
    [string]$LogFile = ".\backups\backup.log"
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
    $logMessage | Tee-Object -FilePath $LogFile -Append

    # Also write to console with color
    switch ($Level) {
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR' { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }
}

function Initialize-Environment {
    # Verify required environment variables
    $requiredVars = @(
        'FROM_ADDRESS',
        'ADMIN_EMAIL',
        'SMTP_HOST',
        'SMTP_PORT',
        'SMTP_USERNAME',
        'SMTP_PASSWORD'
    )

    foreach ($var in $requiredVars) {
        if (-not (Get-Item "env:$var" -ErrorAction SilentlyContinue)) {
            throw "Required environment variable $var is not set"
        }
    }

    # Create backup directory structure
    $script:BackupDate = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $script:CurrentBackupDir = Join-Path $BackupRoot $script:BackupDate
    $script:VerificationDir = Join-Path $script:CurrentBackupDir "verification"

    New-Item -ItemType Directory -Force -Path $script:CurrentBackupDir | Out-Null
    New-Item -ItemType Directory -Force -Path $script:VerificationDir | Out-Null
    Write-Log "Created backup directories"

    # Ensure log directory exists
    $logDir = Split-Path $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Write-Log "Created log directory: $logDir"
    }
}

function Get-FileHashes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Get-ChildItem $Path -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($Path.Length + 1)
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        [PSCustomObject]@{
            RelativePath = $relativePath
            Hash = $hash.Hash
            Size = $_.Length
        }
    }
}

function Test-BackupIntegrity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$BackupDir,
        [Parameter(Mandatory = $true)]
        [string]$Service
    )

    Write-Log "Verifying backup integrity for $Service..." -Level 'INFO'
    $sourceHashes = Get-FileHashes $SourceDir
    $backupHashes = Get-FileHashes $BackupDir

    # Compare file counts
    if ($sourceHashes.Count -ne $backupHashes.Count) {
        throw ("File count mismatch for $Service. Source: $($sourceHashes.Count), Backup: $($backupHashes.Count)")
    }

    # Compare each file
    foreach ($sourceFile in $sourceHashes) {
        $backupFile = $backupHashes | Where-Object { $_.RelativePath -eq $sourceFile.RelativePath }

        if (-not $backupFile) {
            throw ("Missing file in backup: $($sourceFile.RelativePath)")
        }

        if ($sourceFile.Hash -ne $backupFile.Hash) {
            throw ("Hash mismatch for file: $($sourceFile.RelativePath)")
        }

        if ($sourceFile.Size -ne $backupFile.Size) {
            throw ("Size mismatch for file: $($sourceFile.RelativePath)")
        }
    }

    Write-Log "Backup integrity verified for $Service" -Level 'INFO'
}

function Send-BackupNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [ValidateSet('Success', 'Failure')]
        [string]$Type = 'Success'
    )

    $emailParams = @{
        From = $env:FROM_ADDRESS
        To = $env:ADMIN_EMAIL
        Subject = $Subject
        Body = $Body
        SmtpServer = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential(
            $env:SMTP_USERNAME,
            (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force)
        )
    }

    Send-MailMessage @emailParams
    Write-Log "Sent backup $Type notification email" -Level 'INFO'
}

function Backup-Services {
    # Backup docker compose file
    Copy-Item "docker-compose.yml" -Destination "$script:CurrentBackupDir\docker-compose.yml"
    Write-Log "Backed up docker-compose.yml" -Level 'INFO'

    # Backup config directories
    $services = @("radarr", "sonarr", "lidarr", "prowlarr", "bazarr", "readarr", "qbittorrent")
    foreach ($service in $services) {
        $sourceDir = ".\docker\$service"
        if (Test-Path $sourceDir) {
            $archivePath = "$script:CurrentBackupDir\$service.zip"

            Write-Log "Backing up $service configuration..." -Level 'INFO'
            Compress-Archive -Path "$sourceDir\*" -DestinationPath $archivePath -Force

            try {
                Expand-Archive -Path $archivePath -DestinationPath "$script:VerificationDir\$service" -Force
                Test-BackupIntegrity -SourceDir $sourceDir -BackupDir "$script:VerificationDir\$service" -Service $service
            }
            catch {
                Write-Log "Backup verification failed for $service: $_" -Level 'ERROR'
                throw
            }
        }
        else {
            Write-Log "Service directory not found: $sourceDir" -Level 'WARNING'
        }
    }
}

function Remove-OldBackups {
    Get-ChildItem -Path $BackupRoot -Directory | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Write-Log "Cleaned up old backup: $($_.Name)" -Level 'INFO'
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
        Write-Log "Starting backup process..." -Level 'INFO'
        Initialize-Environment
        Backup-Services
        Remove-OldBackups

        $backupSize = Get-BackupSize -BackupPath $script:CurrentBackupDir
        $successMessage = @"
Backup completed successfully.
Location: $script:CurrentBackupDir
Size: $backupSize MB
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

        Send-BackupNotification -Subject "[BACKUP] Success - $(Get-Date -Format 'yyyy-MM-dd')" -Body $successMessage -Type 'Success'
        Write-Log "Backup completed successfully. Total size: $backupSize MB" -Level 'INFO'
    }
    catch {
        $errorMessage = "Backup failed: $_"
        Write-Log $errorMessage -Level 'ERROR'

        Send-BackupNotification -Subject "[BACKUP] FAILED - $(Get-Date -Format 'yyyy-MM-dd')" -Body $errorMessage -Type 'Failure'
        throw
    }
}

# Script execution
Main